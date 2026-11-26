// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {PlinkoRoyale} from "../PlinkoRoyale.sol";
import {MockAGC} from "./mocks/MockAGC.sol";
import {MockVRFWrapper} from "./mocks/MockVRFWrapper.sol";

/// @notice A keeper contract whose receive() tries to reenter draw().
///         Used to prove the reentrancy guard blocks it.
contract ReentrantKeeper {
    PlinkoRoyale public game;
    uint256 public roundId;
    bool public armed;

    constructor(PlinkoRoyale game_) {
        game = game_;
    }

    function arm(uint256 roundId_) external {
        roundId = roundId_;
        armed = true;
    }

    function doDraw() external payable {
        game.draw{value: msg.value}(roundId);
    }

    receive() external payable {
        if (armed) {
            armed = false;
            // Reentrant attempt: must be blocked by the guard, which makes
            // this receive() revert, which makes the refund fail.
            game.draw{value: 0}(roundId);
        }
    }
}

/// @title PlinkoRoyale tests
/// @notice Covers the full lifecycle, exact settlement math against
///         verify.py's worked examples (scaled to token wei), refund paths,
///         entry rules, fee handling, and withdraw safety.
contract PlinkoRoyaleTest is Test {
    MockAGC internal agc;
    MockVRFWrapper internal wrapper;
    PlinkoRoyale internal game;

    address internal feeRecipient = makeAddr("feeRecipient");
    address internal keeper = makeAddr("keeper");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");

    uint256 internal constant T0 = 1_000_000; // deployment time (genesis)
    uint256 internal constant TIER1 = 2_000_000e18;
    uint256 internal constant TIER2 = 5_000_000e18;
    uint256 internal constant TIER3 = 10_000_000e18;
    uint256 internal constant WORD = 12345; // fixed VRF word for slot forcing

    function setUp() public {
        vm.warp(T0);
        agc = new MockAGC();
        wrapper = new MockVRFWrapper();
        game = new PlinkoRoyale(address(agc), feeRecipient, address(wrapper));

        address[4] memory players = [alice, bob, carol, dave];
        for (uint256 i = 0; i < players.length; i++) {
            agc.mint(players[i], 1_000_000_000e18);
            vm.prank(players[i]);
            agc.approve(address(game), type(uint256).max);
        }
        vm.deal(keeper, 100 ether);
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    /// @dev Replicates the contract's slot derivation for test assertions.
    function _slotOf(uint256 word, uint256 roundId, address player, bytes32 seed) internal pure returns (uint8) {
        bytes32 hash = keccak256(abi.encode(word, roundId, player, seed));
        uint8 bits = uint8(uint256(hash) >> 248);
        uint8 count = 0;
        for (uint8 i = 0; i < 8; i++) {
            if (bits & 1 == 1) count++;
            bits >>= 1;
        }
        return count;
    }

    /// @dev Finds a clientSeed that makes `player` land on `targetSlot`
    ///      for the given word/round. Expected trials <= 256.
    function _seedForSlot(uint256 word, uint256 roundId, address player, uint8 targetSlot)
        internal
        pure
        returns (bytes32)
    {
        for (uint256 i = 0; i < 100_000; i++) {
            bytes32 seed = bytes32(i);
            if (_slotOf(word, roundId, player, seed) == targetSlot) return seed;
        }
        revert("seed not found");
    }

    /// @dev Enters `player` into the current round.
    function _enter(address player, uint256 amount, bytes32 seed) internal {
        (uint256 roundId,,) = game.currentRound();
        vm.prank(player);
        game.enter(roundId, amount, seed);
    }

    /// @dev Warps past the current round's close, draws, and fulfills.
    function _closeDrawFulfill(uint256 word) internal returns (uint256 roundId) {
        uint64 closesAt;
        (roundId,, closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1);
        uint256 fee = game.drawFee(1 gwei);
        vm.prank(keeper);
        game.draw{value: fee}(roundId);
        uint256 requestId = wrapper.nextRequestId() - 1;
        wrapper.fulfill(requestId, word);
    }

    /// @dev Enters players with forced slots, settles, returns round id.
    function _runForcedRound(address[] memory players, uint256[] memory stakes, uint8[] memory slots)
        internal
        returns (uint256 roundId)
    {
        (roundId,,) = game.currentRound();
        for (uint256 i = 0; i < players.length; i++) {
            bytes32 seed = _seedForSlot(WORD, roundId, players[i], slots[i]);
            vm.prank(players[i]);
            game.enter(roundId, stakes[i], seed);
        }
        _closeDrawFulfill(WORD);
        game.settle(roundId);
    }

    // ---------------------------------------------------------------
    // Lifecycle
    // ---------------------------------------------------------------

    function testFullLifecycle() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER2, bytes32(uint256(7)));

        (uint256 roundId, uint64 opensAt, uint64 closesAt) = game.currentRound();
        assertEq(roundId, 0);
        assertEq(opensAt, T0);
        assertEq(closesAt, T0 + 60);
        assertEq(game.stakedOf(alice), TIER1);
        assertEq(game.stakedOf(bob), TIER2);

        _closeDrawFulfill(WORD);
        game.settle(roundId);

        // Conservation: everything credited or taken, dust left behind.
        uint256 pot = TIER1 + TIER2;
        uint256 burn = (pot * 30) / 10_000;
        uint256 fee = (pot * 30) / 10_000;
        (, , , , , , uint256 burned, uint256 feePaid, uint256 dust) = game.roundDetail(roundId);
        assertEq(burned, burn);
        assertEq(feePaid, fee);
        assertEq(game.balanceOf(alice) + game.balanceOf(bob) + burn + fee + dust, pot);
        assertEq(agc.balanceOf(game.DEAD_ADDRESS()), burn);
        assertEq(agc.balanceOf(feeRecipient), fee);
        assertEq(game.stakedOf(alice), 0);
        assertEq(game.stakedOf(bob), 0);

        // Slots match the public derivation.
        (, uint256 payoutA, uint8 slotA) = game.result(roundId, alice);
        assertEq(slotA, _slotOf(WORD, roundId, alice, bytes32(0)));
        assertEq(payoutA, game.balanceOf(alice));

        // Withdraw everything; only dust remains in the contract.
        uint256 balA = game.balanceOf(alice);
        vm.prank(alice);
        game.withdraw(balA);
        assertEq(agc.balanceOf(alice), 1_000_000_000e18 - TIER1 + balA);
        uint256 balB = game.balanceOf(bob);
        vm.prank(bob);
        game.withdraw(balB);
        assertEq(agc.balanceOf(address(game)), dust);
    }

    function testPhaseReporting() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER1, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();

        (uint8 phase,,,,,,,,) = game.roundDetail(roundId);
        assertEq(phase, 0); // Open

        vm.warp(uint256(closesAt) + 1);
        (phase,,,,,,,,) = game.roundDetail(roundId);
        assertEq(phase, 1); // AwaitingDraw (derived)

        uint256 fee = game.drawFee(1 gwei);
        vm.prank(keeper);
        game.draw{value: fee}(roundId);
        (phase,,,,,,,,) = game.roundDetail(roundId);
        assertEq(phase, 2); // AwaitingRandom

        wrapper.fulfill(wrapper.nextRequestId() - 1, WORD);
        game.settle(roundId);
        (phase,,,,,,,,) = game.roundDetail(roundId);
        assertEq(phase, 3); // Settled
    }

    /// @dev External-audit LOW-1: exactly at closesAt the round is already
    ///      closed (enter/draw act on the next round), so roundDetail must
    ///      report phase 1, not 0.
    function testPhaseBoundaryAtClose() public {
        _enter(alice, TIER1, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();

        vm.warp(uint256(closesAt) - 1);
        (uint8 phase,,,,,,,,) = game.roundDetail(roundId);
        assertEq(phase, 0); // still Open one second before close

        vm.warp(uint256(closesAt));
        (phase,,,,,,,,) = game.roundDetail(roundId);
        assertEq(phase, 1); // AwaitingDraw exactly at close

        vm.prank(bob);
        vm.expectRevert();
        game.enter(roundId, TIER1, bytes32(0));
    }

    /// @dev Views added for exact UI/agent gating: wordReceivedOf tracks
    ///      fulfillment independently of the word value, and
    ///      drawRequestedAtOf exposes the RANDOM_TIMEOUT anchor.
    function testWordReceivedAndDrawRequestedAtViews() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER1, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();

        assertFalse(game.wordReceivedOf(roundId));
        assertEq(game.drawRequestedAtOf(roundId), 0);

        vm.warp(uint256(closesAt) + 1);
        uint256 fee = game.drawFee(1 gwei);
        vm.prank(keeper);
        game.draw{value: fee}(roundId);

        assertEq(game.drawRequestedAtOf(roundId), uint256(closesAt) + 1);
        assertFalse(game.wordReceivedOf(roundId));

        wrapper.fulfill(wrapper.nextRequestId() - 1, WORD);
        assertTrue(game.wordReceivedOf(roundId));
        assertEq(game.randomWordOf(roundId), WORD);
    }

    function testSevenStakeTiers() public {
        // The ladder mirrors Battle Royale: 100K/300K/500K/1M/2M/5M/10M.
        uint256[7] memory tiers = game.stakeTiers();
        assertEq(tiers[0], 100_000e18);
        assertEq(tiers[1], 300_000e18);
        assertEq(tiers[2], 500_000e18);
        assertEq(tiers[3], 1_000_000e18);
        assertEq(tiers[4], 2_000_000e18);
        assertEq(tiers[5], 5_000_000e18);
        assertEq(tiers[6], 10_000_000e18);

        // The smallest tier is enterable.
        _enter(alice, tiers[0], bytes32(0));
        (uint256 roundId,,) = game.currentRound();
        (uint256 stake,,,) = game.entryOf(roundId, alice);
        assertEq(stake, 100_000e18);

        // A non-tier amount still reverts.
        vm.prank(bob);
        vm.expectRevert(bytes("amount not a stake tier"));
        game.enter(roundId, 200_000e18, bytes32(0));
    }

    // ---------------------------------------------------------------
    // Exact settlement math vs verify.py worked examples (wei-scaled)
    // ---------------------------------------------------------------

    function testWorkedExample1() public {
        address[] memory players = new address[](4);
        players[0] = alice;
        players[1] = bob;
        players[2] = carol;
        players[3] = dave;
        uint256[] memory stakes = new uint256[](4);
        stakes[0] = TIER1;
        stakes[1] = TIER1;
        stakes[2] = TIER2;
        stakes[3] = TIER3;
        uint8[] memory slots = new uint8[](4);
        slots[0] = 4;
        slots[1] = 0;
        slots[2] = 2;
        slots[3] = 3;

        uint256 roundId = _runForcedRound(players, stakes, slots);

        // Expected values: verify.py settle_round with stakes x 1e18.
        assertEq(game.balanceOf(alice), 397_600e18);
        assertEq(game.balanceOf(bob), 11_530_400e18);
        assertEq(game.balanceOf(carol), 3_479_000e18);
        assertEq(game.balanceOf(dave), 3_479_000e18);
        (, , , , , , uint256 burned, uint256 feePaid, uint256 dust) = game.roundDetail(roundId);
        assertEq(burned, 57_000e18);
        assertEq(feePaid, 57_000e18);
        assertEq(dust, 0);
    }

    function testWorkedExample2() public {
        address[] memory players = new address[](3);
        players[0] = alice;
        players[1] = bob;
        players[2] = carol;
        uint256[] memory stakes = new uint256[](3);
        stakes[0] = TIER1;
        stakes[1] = TIER2;
        stakes[2] = TIER3;
        uint8[] memory slots = new uint8[](3);
        slots[0] = 4;
        slots[1] = 4;
        slots[2] = 4;

        uint256 roundId = _runForcedRound(players, stakes, slots);

        assertEq(game.balanceOf(alice), 1_988_000e18);
        assertEq(game.balanceOf(bob), 4_970_000e18);
        assertEq(game.balanceOf(carol), 9_940_000e18);
        (, , , , , , uint256 burned, uint256 feePaid, uint256 dust) = game.roundDetail(roundId);
        assertEq(burned, 51_000e18);
        assertEq(feePaid, 51_000e18);
        assertEq(dust, 0);
    }

    function testWorkedExample3() public {
        address[] memory players = new address[](3);
        players[0] = alice;
        players[1] = bob;
        players[2] = carol;
        uint256[] memory stakes = new uint256[](3);
        stakes[0] = TIER1;
        stakes[1] = TIER1;
        stakes[2] = TIER1;
        uint8[] memory slots = new uint8[](3);
        slots[0] = 0;
        slots[1] = 4;
        slots[2] = 4;

        uint256 roundId = _runForcedRound(players, stakes, slots);

        // Wei-exact values from verify.py (flooring dust = 2 wei here).
        assertEq(game.balanceOf(alice), 5_579_225_806_451_612_903_225_806);
        assertEq(game.balanceOf(bob), 192_387_096_774_193_548_387_096);
        assertEq(game.balanceOf(carol), 192_387_096_774_193_548_387_096);
        (, , , , , , uint256 burned, uint256 feePaid, uint256 dust) = game.roundDetail(roundId);
        assertEq(burned, 18_000e18);
        assertEq(feePaid, 18_000e18);
        assertEq(dust, 2);
    }

    /// @notice Fuzz: conservation + bounds hold for random rounds.
    function testFuzzConservation(uint256 word, uint8 playerCountRaw, uint256 stakeSeed) public {
        uint256 n = bound(playerCountRaw, 2, 20);
        address[] memory players = new address[](n);
        uint256 pot = 0;
        (uint256 roundId,,) = game.currentRound();
        for (uint256 i = 0; i < n; i++) {
            players[i] = address(uint160(0x10000 + i));
            uint256 pick = uint256(keccak256(abi.encode(stakeSeed, i))) % 3;
            uint256 stake = pick == 0 ? TIER1 : (pick == 1 ? TIER2 : TIER3);
            pot += stake;
            agc.mint(players[i], stake);
            vm.startPrank(players[i]);
            agc.approve(address(game), stake);
            game.enter(roundId, stake, keccak256(abi.encode(stakeSeed, i)));
            vm.stopPrank();
        }

        _closeDrawFulfill(word);
        game.settle(roundId);

        uint256 burn = (pot * 30) / 10_000;
        uint256 fee = (pot * 30) / 10_000;
        (, , , , , , uint256 burned, uint256 feePaid, uint256 dust) = game.roundDetail(roundId);
        assertEq(burned, burn);
        assertEq(feePaid, fee);
        assertLt(dust, n); // flooring bound: dust < players

        uint256 credited = 0;
        for (uint256 i = 0; i < n; i++) {
            uint256 bal = game.balanceOf(players[i]);
            assertLe(bal, pot); // nobody wins more than the pot
            credited += bal;
        }
        assertEq(credited + burn + fee + dust, pot); // exact conservation
        assertEq(agc.balanceOf(address(game)), credited + dust);
    }

    // ---------------------------------------------------------------
    // Entry rules
    // ---------------------------------------------------------------

    function testOneEntryPerRound() public {
        _enter(alice, TIER1, bytes32(0));
        (uint256 roundId,,) = game.currentRound();
        vm.prank(alice);
        vm.expectRevert("already entered");
        game.enter(roundId, TIER1, bytes32(0));
    }

    function testRoundFullAtMaxPlayers() public {
        (uint256 roundId,,) = game.currentRound();
        uint256 maxPlayers = game.MAX_PLAYERS();
        assertEq(maxPlayers, 500);
        for (uint256 i = 0; i < maxPlayers; i++) {
            address player = address(uint160(0x10000 + i));
            agc.mint(player, TIER1);
            vm.prank(player);
            agc.approve(address(game), TIER1);
            vm.prank(player);
            game.enter(roundId, TIER1, bytes32(0));
        }
        address extra = address(uint160(0x99999));
        agc.mint(extra, TIER1);
        vm.prank(extra);
        agc.approve(address(game), TIER1);
        vm.prank(extra);
        vm.expectRevert("round full");
        game.enter(roundId, TIER1, bytes32(0));

        // A full round must still settle in one transaction, conserving the pot.
        _closeDrawFulfill(WORD);
        game.settle(roundId);
        (, , , uint256 totalStaked, uint256 playerCount, , uint256 burned, uint256 feePaid, uint256 dust) =
            game.roundDetail(roundId);
        assertEq(playerCount, maxPlayers);
        assertEq(totalStaked, maxPlayers * TIER1);
        assertEq(burned, (totalStaked * 30) / 10_000);
        assertEq(feePaid, (totalStaked * 30) / 10_000);
        assertLt(dust, maxPlayers);
    }

    function testPlayersOf() public {
        (uint256 roundId,,) = game.currentRound();
        // Empty round (and a round that does not exist yet) -> empty array.
        assertEq(game.playersOf(roundId).length, 0);
        assertEq(game.playersOf(roundId + 100).length, 0);

        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER2, bytes32(0));
        _enter(carol, TIER3, bytes32(0));

        address[] memory players = game.playersOf(roundId);
        assertEq(players.length, 3);
        assertEq(players[0], alice);
        assertEq(players[1], bob);
        assertEq(players[2], carol);

        // playersOf agrees with roundDetail's playerCount.
        (, , , , uint256 playerCount, , , ,) = game.roundDetail(roundId);
        assertEq(playerCount, players.length);

        // The list survives settlement unchanged.
        _closeDrawFulfill(WORD);
        game.settle(roundId);
        address[] memory afterSettle = game.playersOf(roundId);
        assertEq(afterSettle.length, 3);
        assertEq(afterSettle[0], alice);
        assertEq(afterSettle[1], bob);
        assertEq(afterSettle[2], carol);
    }

    function testTierEnforcement() public {
        (uint256 roundId,,) = game.currentRound();
        vm.prank(alice);
        vm.expectRevert("amount not a stake tier");
        game.enter(roundId, 3_000_000e18, bytes32(0));
        vm.prank(alice);
        vm.expectRevert("amount not a stake tier");
        game.enter(roundId, 0, bytes32(0));
    }

    function testEnterWrongRound() public {
        vm.prank(alice);
        vm.expectRevert("round not open");
        game.enter(7, TIER1, bytes32(0));
    }

    function testEnterAfterClose() public {
        (, , uint64 closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1);
        // Round 0 is closed; current round is now 1.
        vm.prank(alice);
        vm.expectRevert("round not open");
        game.enter(0, TIER1, bytes32(0));
    }

    function testTaxedTransferReverts() public {
        agc.setTaxBps(200); // 2% transfer tax, like a taxed token would do
        (uint256 roundId,,) = game.currentRound();
        vm.prank(alice);
        vm.expectRevert("stake transfer taxed");
        game.enter(roundId, TIER1, bytes32(0));
    }

    // ---------------------------------------------------------------
    // Draw rules
    // ---------------------------------------------------------------

    function testDrawTooFewPlayers() public {
        _enter(alice, TIER1, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1);
        vm.prank(keeper);
        vm.expectRevert("too few players, use refund");
        game.draw{value: 1 ether}(roundId);
    }

    function testDrawBeforeCloseReverts() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER1, bytes32(0));
        (uint256 roundId,,) = game.currentRound();
        vm.prank(keeper);
        vm.expectRevert("round still open");
        game.draw{value: 1 ether}(roundId);
    }

    function testDrawInsufficientFee() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER1, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1);
        vm.prank(keeper);
        vm.expectRevert("insufficient VRF fee");
        game.draw{value: 0}(roundId);
    }

    function testDrawExcessFeeRefunded() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER1, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1);

        uint256 fee = game.drawFee(1 gwei);
        uint256 keeperBefore = keeper.balance;
        vm.prank(keeper);
        game.draw{value: fee + 5 ether}(roundId);
        // Keeper paid exactly the fee; the 5 ether excess came back.
        assertEq(keeper.balance, keeperBefore - fee);
        assertEq(address(wrapper).balance, fee);
    }

    function testDrawTwiceReverts() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER1, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1);
        uint256 fee = game.drawFee(1 gwei);
        vm.prank(keeper);
        game.draw{value: fee}(roundId);
        vm.prank(keeper);
        vm.expectRevert("round not awaiting draw");
        game.draw{value: fee}(roundId);
    }

    function testReentrantDrawBlocked() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER1, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1);

        ReentrantKeeper rk = new ReentrantKeeper(game);
        rk.arm(roundId);
        vm.deal(address(rk), 10 ether);
        uint256 fee = game.drawFee(1 gwei);
        // Excess refund triggers receive(), which reenters draw() and is
        // blocked by the guard -> refund fails -> whole draw reverts.
        vm.expectRevert("fee refund failed");
        rk.doDraw{value: fee + 1 ether}();
    }

    function testCallbackOnlyFromWrapper() public {
        uint256[] memory words = new uint256[](1);
        words[0] = 1;
        vm.prank(alice);
        vm.expectRevert("only wrapper");
        game.rawFulfillRandomWords(1, words);
    }

    // ---------------------------------------------------------------
    // Refund paths
    // ---------------------------------------------------------------

    function testRefundSinglePlayer() public {
        _enter(alice, TIER2, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1);

        game.refund(roundId);
        assertEq(game.balanceOf(alice), TIER2); // full stake back
        assertEq(game.stakedOf(alice), 0);
        assertEq(agc.balanceOf(game.DEAD_ADDRESS()), 0); // no burn
        assertEq(agc.balanceOf(feeRecipient), 0); // no fee
        (uint8 phase,,,,,,,,) = game.roundDetail(roundId);
        assertEq(phase, 4); // Refunded

        vm.prank(alice);
        game.withdraw(TIER2);
        assertEq(agc.balanceOf(alice), 1_000_000_000e18);
    }

    function testRefundDrawTimeout() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER3, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();

        // Too early: round closed but 1h draw window not over.
        vm.warp(uint256(closesAt) + 1);
        vm.expectRevert("refund not available yet");
        game.refund(roundId);

        vm.warp(uint256(closesAt) + 1 hours + 1);
        game.refund(roundId);
        assertEq(game.balanceOf(alice), TIER1);
        assertEq(game.balanceOf(bob), TIER3);
    }

    function testRefundRandomTimeout() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER1, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1);
        uint256 fee = game.drawFee(1 gwei);
        vm.prank(keeper);
        game.draw{value: fee}(roundId);

        // Too early: word may still arrive.
        vm.expectRevert("refund not available yet");
        game.refund(roundId);

        vm.warp(block.timestamp + 1 hours + 1);
        game.refund(roundId);
        assertEq(game.balanceOf(alice), TIER1);
        assertEq(game.balanceOf(bob), TIER1);

        // A late word now reverts in the callback; round stays refunded.
        uint256 requestId = wrapper.nextRequestId() - 1;
        vm.expectRevert("round not awaiting random");
        wrapper.fulfill(requestId, WORD);
    }

    function testNoRefundAfterWordArrives() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER1, bytes32(0));
        uint256 roundId = _closeDrawFulfill(WORD);
        vm.expectRevert("word received, settle instead");
        game.refund(roundId);
    }

    function testSettleBeforeWordReverts() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER1, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1);
        uint256 fee = game.drawFee(1 gwei);
        vm.prank(keeper);
        game.draw{value: fee}(roundId);
        vm.expectRevert("word not received yet");
        game.settle(roundId);
    }

    function testDoubleSettleReverts() public {
        _enter(alice, TIER1, bytes32(0));
        _enter(bob, TIER1, bytes32(0));
        uint256 roundId = _closeDrawFulfill(WORD);
        game.settle(roundId);
        vm.expectRevert("round not awaiting random");
        game.settle(roundId);
    }

    // ---------------------------------------------------------------
    // Withdraw safety
    // ---------------------------------------------------------------

    function testWithdrawRules() public {
        _enter(alice, TIER1, bytes32(0));
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1);
        game.refund(roundId);

        vm.prank(alice);
        vm.expectRevert("amount is zero");
        game.withdraw(0);

        vm.prank(alice);
        vm.expectRevert("insufficient balance");
        game.withdraw(TIER1 + 1);

        vm.prank(alice);
        game.withdraw(TIER1);
        vm.prank(alice);
        vm.expectRevert("insufficient balance");
        game.withdraw(1);
    }

    // ---------------------------------------------------------------
    // Gas measurement for the settle loop bound (see CONTRACT.md)
    // ---------------------------------------------------------------

    function _gasRound(uint256 n) internal returns (uint256 settleGas, uint256 callbackGasUsed) {
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        for (uint256 i = 0; i < n; i++) {
            address p = address(uint160(0x20000 + i));
            agc.mint(p, TIER1);
            vm.startPrank(p);
            agc.approve(address(game), TIER1);
            game.enter(roundId, TIER1, bytes32(i));
            vm.stopPrank();
        }
        vm.warp(uint256(closesAt) + 1);
        uint256 fee = game.drawFee(1 gwei);
        vm.prank(keeper);
        game.draw{value: fee}(roundId);

        uint256 requestId = wrapper.nextRequestId() - 1;
        uint256 g0 = gasleft();
        wrapper.fulfill(requestId, WORD);
        callbackGasUsed = g0 - gasleft();

        g0 = gasleft();
        game.settle(roundId);
        settleGas = g0 - gasleft();
    }

    function testSettleGas100Players() public {
        (uint256 settleGas, uint256 callbackGas) = _gasRound(100);
        console2.log("settle gas, 100 players:", settleGas);
        console2.log("per player:", settleGas / 100);
        console2.log("callback gas (incl. mock overhead):", callbackGas);
        assertLt(settleGas, 6_000_000);
    }

    function testSettleGas300Players() public {
        (uint256 settleGas,) = _gasRound(300);
        console2.log("settle gas, 300 players:", settleGas);
        console2.log("per player:", settleGas / 300);
        assertLt(settleGas, 18_000_000);
    }
}
