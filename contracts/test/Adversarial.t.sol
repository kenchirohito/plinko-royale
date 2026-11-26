// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {PlinkoRoyale} from "../PlinkoRoyale.sol";
import {MockAGC} from "./mocks/MockAGC.sol";
import {MockVRFWrapper} from "./mocks/MockVRFWrapper.sol";

// =====================================================================
// Adversarial mocks (audit additions — not part of the original suite)
// =====================================================================

/// @notice ERC777-style token: after moving balances it can (a) call a
///         receiver hook on the recipient, and/or (b) fire an arbitrary
///         armed call (used to attempt reentrancy into the game).
///         Also supports pause + recipient blocklist to model a token
///         that stops cooperating after entries are in.
contract HookToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    bool public paused;
    mapping(address => bool) public blocked; // transfers TO these revert

    // ERC777-style receiver hook switch, per recipient.
    mapping(address => bool) public receiverHook;

    // Generic armed call fired after every transfer/transferFrom.
    address public hookTarget;
    bytes public hookData;
    bool public hookArmed;
    bool public hookOk;
    uint256 public hookFires;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function setPaused(bool p) external {
        paused = p;
    }

    function setBlocked(address who, bool b) external {
        blocked[who] = b;
    }

    function setReceiverHook(address who, bool on) external {
        receiverHook[who] = on;
    }

    function armHook(address target, bytes calldata data) external {
        hookTarget = target;
        hookData = data;
        hookArmed = true;
        hookOk = false;
        hookFires = 0;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        _afterTransfer(to);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance too low");
        allowance[from][msg.sender] = allowed - amount;
        _move(from, to, amount);
        _afterTransfer(to);
        return true;
    }

    function _move(address from, address to, uint256 amount) internal {
        require(!paused, "paused");
        require(!blocked[to], "recipient blocked");
        require(balanceOf[from] >= amount, "balance too low");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function _afterTransfer(address to) internal {
        if (receiverHook[to]) {
            IReceiver(to).onTokensReceived();
        }
        if (hookArmed) {
            hookArmed = false; // fire once
            hookFires++;
            (bool ok,) = hookTarget.call(hookData);
            hookOk = ok;
        }
    }
}

interface IReceiver {
    function onTokensReceived() external;
}

/// @notice Contract player that tries to reenter withdraw() from its
///         token-receiver hook (ERC777-style reentrancy attempt).
contract EvilPlayer is IReceiver {
    PlinkoRoyale public game;
    HookToken public token;
    uint256 public reentryAttempts;
    bool public reentrySucceeded;

    constructor(PlinkoRoyale game_, HookToken token_) {
        game = game_;
        token = token_;
    }

    function join(uint256 roundId, uint256 amount) external {
        token.approve(address(game), amount);
        game.enter(roundId, amount, bytes32(0));
    }

    function attackWithdraw(uint256 amount) external {
        game.withdraw(amount);
    }

    function onTokensReceived() external override {
        reentryAttempts++;
        try game.withdraw(1) {
            reentrySucceeded = true;
        } catch {
            reentrySucceeded = false;
        }
    }
}

/// @notice Token that can be switched to return false on transfer, or to
///         lie on transferFrom (return true, move nothing).
contract FalseToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    bool public failTransfer;
    bool public lieTransferFrom;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function setFailTransfer(bool f) external {
        failTransfer = f;
    }

    function setLieTransferFrom(bool f) external {
        lieTransferFrom = f;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (failTransfer) return false;
        require(balanceOf[msg.sender] >= amount, "balance too low");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (lieTransferFrom) return true; // moves nothing
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance too low");
        allowance[from][msg.sender] = allowed - amount;
        require(balanceOf[from] >= amount, "balance too low");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice USDT-style token whose transfer functions return NOTHING.
contract NoReturnToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "balance too low");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance too low");
        allowance[from][msg.sender] = allowed - amount;
        require(balanceOf[from] >= amount, "balance too low");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

/// @notice VRF wrapper stand-in that returns requestId 0 (pathological).
contract ZeroIdWrapper {
    function calculateRequestPriceNative(uint32, uint32) external pure returns (uint256) {
        return 0.001 ether;
    }

    function estimateRequestPriceNative(uint32, uint32, uint256) external pure returns (uint256) {
        return 0.001 ether;
    }

    function requestRandomWordsInNative(uint32, uint16, uint32, bytes calldata)
        external
        payable
        returns (uint256)
    {
        return 0;
    }

    function fulfillZero(address consumer) external {
        uint256[] memory words = new uint256[](1);
        words[0] = 42;
        IVRFConsumerZ(consumer).rawFulfillRandomWords(0, words);
    }

    receive() external payable {}
}

interface IVRFConsumerZ {
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata words) external;
}

/// @notice Keeper contract with NO receive()/fallback — cannot take the
///         excess-fee BNB refund from draw().
contract NoReceiveKeeper {
    function doDraw(PlinkoRoyale game, uint256 roundId) external payable {
        game.draw{value: msg.value}(roundId);
    }
}

// =====================================================================
// Adversarial tests
// =====================================================================

contract PlinkoRoyaleAdversarialTest is Test {
    MockAGC internal agc;
    MockVRFWrapper internal wrapper;
    PlinkoRoyale internal game;

    address internal feeRecipient = makeAddr("feeRecipient");
    address internal keeper = makeAddr("keeper");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant T0 = 1_000_000;
    uint256 internal constant TIER1 = 2_000_000e18;
    uint256 internal constant TIER2 = 5_000_000e18;
    uint256 internal constant WORD = 12345;

    function setUp() public {
        vm.warp(T0);
        agc = new MockAGC();
        wrapper = new MockVRFWrapper();
        game = new PlinkoRoyale(address(agc), feeRecipient, address(wrapper));
        address[3] memory players = [alice, bob, carol];
        for (uint256 i = 0; i < players.length; i++) {
            agc.mint(players[i], 1_000_000_000e18);
            vm.prank(players[i]);
            agc.approve(address(game), type(uint256).max);
        }
        vm.deal(keeper, 100 ether);
        vm.deal(stranger, 100 ether);
    }

    // --- helpers -----------------------------------------------------

    function _enter(address player, uint256 amount) internal returns (uint256 roundId) {
        (roundId,,) = game.currentRound();
        vm.prank(player);
        game.enter(roundId, amount, bytes32(0));
    }

    function _closeAndDraw(PlinkoRoyale g, MockVRFWrapper w) internal returns (uint256 roundId) {
        uint64 closesAt;
        (roundId,, closesAt) = g.currentRound();
        vm.warp(uint256(closesAt) + 1);
        uint256 fee = g.drawFee(1 gwei);
        vm.prank(keeper);
        g.draw{value: fee}(roundId);
    }

    function _fulfill(MockVRFWrapper w, uint256 word) internal {
        w.fulfill(w.nextRequestId() - 1, word);
    }

    // --- reentrancy --------------------------------------------------

    /// @notice ERC777-style reentrant withdraw must be blocked; the player
    ///         is paid exactly once.
    function testReentrantWithdrawBlocked() public {
        HookToken ht = new HookToken();
        MockVRFWrapper w = new MockVRFWrapper();
        PlinkoRoyale g = new PlinkoRoyale(address(ht), feeRecipient, address(w));
        EvilPlayer evil = new EvilPlayer(g, ht);

        ht.mint(address(evil), 100_000_000e18);
        ht.mint(alice, 100_000_000e18);
        vm.prank(alice);
        ht.approve(address(g), type(uint256).max);

        (uint256 roundId,,) = g.currentRound();
        evil.join(roundId, TIER1);
        vm.prank(alice);
        g.enter(roundId, TIER1, bytes32(0));

        _closeAndDraw(g, w);
        _fulfill(w, WORD);
        g.settle(roundId);

        uint256 payout = g.balanceOf(address(evil));
        assertGt(payout, 0);

        ht.setReceiverHook(address(evil), true);
        evil.attackWithdraw(payout);

        assertEq(evil.reentryAttempts(), 1);
        assertFalse(evil.reentrySucceeded());
        assertEq(ht.balanceOf(address(evil)), 100_000_000e18 - TIER1 + payout);
        assertEq(g.balanceOf(address(evil)), 0);
    }

    /// @notice A token hook firing during settle's burn transfer must not
    ///         be able to reenter settle() or refund().
    function testReentrantSettleAndRefundBlocked() public {
        HookToken ht = new HookToken();
        MockVRFWrapper w = new MockVRFWrapper();
        PlinkoRoyale g = new PlinkoRoyale(address(ht), feeRecipient, address(w));
        ht.mint(alice, 100_000_000e18);
        ht.mint(bob, 100_000_000e18);
        vm.startPrank(alice);
        ht.approve(address(g), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(bob);
        ht.approve(address(g), type(uint256).max);
        vm.stopPrank();

        (uint256 roundId,,) = g.currentRound();
        vm.prank(alice);
        g.enter(roundId, TIER1, bytes32(0));
        vm.prank(bob);
        g.enter(roundId, TIER2, bytes32(0));
        _closeAndDraw(g, w);
        _fulfill(w, WORD);

        // Arm: during settle's first transfer, try to settle again.
        ht.armHook(address(g), abi.encodeCall(PlinkoRoyale.settle, (roundId)));
        g.settle(roundId);
        assertEq(ht.hookFires(), 1);
        assertFalse(ht.hookOk()); // inner settle reverted (guard)

        (uint8 phase,,,,,,,,) = g.roundDetail(roundId);
        assertEq(phase, 3); // Settled, exactly once
        (, , , , , , uint256 burned, uint256 feePaid, uint256 dust) = g.roundDetail(roundId);
        assertEq(burned, ((TIER1 + TIER2) * 30) / 10_000);
        assertEq(feePaid, ((TIER1 + TIER2) * 30) / 10_000);
        assertEq(g.balanceOf(alice) + g.balanceOf(bob) + burned + feePaid + dust, TIER1 + TIER2);
        assertEq(ht.balanceOf(g.DEAD_ADDRESS()), burned);
        assertEq(ht.balanceOf(feeRecipient), feePaid);
        assertLt(dust, 2); // flooring bound: dust < players
    }

    /// @notice A token hook firing during enter's transferFrom must not be
    ///         able to reenter enter().
    function testReentrantEnterBlocked() public {
        HookToken ht = new HookToken();
        MockVRFWrapper w = new MockVRFWrapper();
        PlinkoRoyale g = new PlinkoRoyale(address(ht), feeRecipient, address(w));
        ht.mint(alice, 100_000_000e18);
        vm.prank(alice);
        ht.approve(address(g), type(uint256).max);

        (uint256 roundId,,) = g.currentRound();
        ht.armHook(address(g), abi.encodeCall(PlinkoRoyale.enter, (roundId, TIER1, bytes32(0))));
        vm.prank(alice);
        g.enter(roundId, TIER1, bytes32(0));

        assertEq(ht.hookFires(), 1);
        assertFalse(ht.hookOk()); // inner enter reverted (guard)
        (uint256 stake,,,) = g.entryOf(roundId, alice);
        assertEq(stake, TIER1); // entered exactly once
        assertEq(ht.balanceOf(address(g)), TIER1);
    }

    // --- hostile / broken tokens --------------------------------------

    /// @notice Lying transferFrom (returns true, moves nothing) is caught
    ///         by the balance-delta check in enter().
    function testLyingTransferFromCaught() public {
        FalseToken ft = new FalseToken();
        MockVRFWrapper w = new MockVRFWrapper();
        PlinkoRoyale g = new PlinkoRoyale(address(ft), feeRecipient, address(w));
        ft.mint(alice, 100_000_000e18);
        vm.prank(alice);
        ft.approve(address(g), type(uint256).max);

        ft.setLieTransferFrom(true);
        (uint256 roundId,,) = g.currentRound();
        vm.prank(alice);
        vm.expectRevert("stake transfer taxed");
        g.enter(roundId, TIER1, bytes32(0));
    }

    /// @notice transfer() returning false: settle and withdraw revert
    ///         cleanly with no state corruption; both succeed once the
    ///         token cooperates again.
    function testFalseTransferRevertsCleanly() public {
        FalseToken ft = new FalseToken();
        MockVRFWrapper w = new MockVRFWrapper();
        PlinkoRoyale g = new PlinkoRoyale(address(ft), feeRecipient, address(w));
        ft.mint(alice, 100_000_000e18);
        ft.mint(bob, 100_000_000e18);
        vm.prank(alice);
        ft.approve(address(g), type(uint256).max);
        vm.prank(bob);
        ft.approve(address(g), type(uint256).max);

        (uint256 roundId,,) = g.currentRound();
        vm.prank(alice);
        g.enter(roundId, TIER1, bytes32(0));
        vm.prank(bob);
        g.enter(roundId, TIER1, bytes32(0));
        _closeAndDraw(g, w);
        _fulfill(w, WORD);

        ft.setFailTransfer(true);
        vm.expectRevert("burn transfer failed");
        g.settle(roundId);
        // No partial state: still awaiting random, nothing credited.
        (uint8 phase,,,,,,,,) = g.roundDetail(roundId);
        assertEq(phase, 2);
        assertEq(g.balanceOf(alice), 0);
        assertEq(g.stakedOf(alice), TIER1);

        ft.setFailTransfer(false);
        g.settle(roundId);
        uint256 bal = g.balanceOf(alice);
        assertGt(bal, 0);

        ft.setFailTransfer(true);
        vm.prank(alice);
        vm.expectRevert("withdraw transfer failed");
        g.withdraw(bal);
        assertEq(g.balanceOf(alice), bal); // debit rolled back

        ft.setFailTransfer(false);
        vm.prank(alice);
        g.withdraw(bal);
        assertEq(ft.balanceOf(alice), 100_000_000e18 - TIER1 + bal);
    }

    /// @notice No-return (USDT-style) token: enter() reverts on ABI decode;
    ///         the game requires a bool-returning ERC20.
    function testNoReturnTokenEnterReverts() public {
        NoReturnToken nt = new NoReturnToken();
        MockVRFWrapper w = new MockVRFWrapper();
        PlinkoRoyale g = new PlinkoRoyale(address(nt), feeRecipient, address(w));
        nt.mint(alice, 100_000_000e18);
        vm.prank(alice);
        nt.approve(address(g), type(uint256).max);

        (uint256 roundId,,) = g.currentRound();
        vm.prank(alice);
        vm.expectRevert(); // returndata decode failure
        g.enter(roundId, TIER1, bytes32(0));
    }

    /// @notice Token pauses after the word arrives: settle bricks, refund
    ///         is blocked (word received), funds wait until unpause.
    ///         Demonstrates the token-trust lockup window.
    function testPausedTokenBricksSettleUntilUnpaused() public {
        HookToken ht = new HookToken();
        MockVRFWrapper w = new MockVRFWrapper();
        PlinkoRoyale g = new PlinkoRoyale(address(ht), feeRecipient, address(w));
        ht.mint(alice, 100_000_000e18);
        ht.mint(bob, 100_000_000e18);
        vm.prank(alice);
        ht.approve(address(g), type(uint256).max);
        vm.prank(bob);
        ht.approve(address(g), type(uint256).max);

        (uint256 roundId,,) = g.currentRound();
        vm.prank(alice);
        g.enter(roundId, TIER1, bytes32(0));
        vm.prank(bob);
        g.enter(roundId, TIER1, bytes32(0));
        _closeAndDraw(g, w);
        _fulfill(w, WORD);

        ht.setPaused(true);
        vm.expectRevert("paused");
        g.settle(roundId);
        // No escape hatch while paused: refund is blocked by the word.
        vm.expectRevert("word received, settle instead");
        g.refund(roundId);
        // Even after the random timeout, refund stays blocked.
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert("word received, settle instead");
        g.refund(roundId);

        ht.setPaused(false);
        g.settle(roundId); // recovers fully once token cooperates
        (uint8 phase,,,,,,,,) = g.roundDetail(roundId);
        assertEq(phase, 3);
    }

    /// @notice Token blocklists the fee recipient: settle reverts at the
    ///         fee transfer (burn rolls back too) and the round cannot
    ///         settle or refund until the block is lifted.
    function testBlockedFeeRecipientBricksSettle() public {
        HookToken ht = new HookToken();
        MockVRFWrapper w = new MockVRFWrapper();
        PlinkoRoyale g = new PlinkoRoyale(address(ht), feeRecipient, address(w));
        ht.mint(alice, 100_000_000e18);
        ht.mint(bob, 100_000_000e18);
        vm.prank(alice);
        ht.approve(address(g), type(uint256).max);
        vm.prank(bob);
        ht.approve(address(g), type(uint256).max);

        (uint256 roundId,,) = g.currentRound();
        vm.prank(alice);
        g.enter(roundId, TIER1, bytes32(0));
        vm.prank(bob);
        g.enter(roundId, TIER1, bytes32(0));
        _closeAndDraw(g, w);
        _fulfill(w, WORD);

        ht.setBlocked(feeRecipient, true);
        vm.expectRevert("recipient blocked");
        g.settle(roundId);
        // Atomic: the burn transfer rolled back as well.
        assertEq(ht.balanceOf(g.DEAD_ADDRESS()), 0);
        assertEq(g.balanceOf(alice), 0);

        ht.setBlocked(feeRecipient, false);
        g.settle(roundId);
        assertGt(ht.balanceOf(feeRecipient), 0);
    }

    /// @notice Same brick if the token blocks the dead (burn) address.
    function testBlockedDeadAddressBricksSettle() public {
        HookToken ht = new HookToken();
        MockVRFWrapper w = new MockVRFWrapper();
        PlinkoRoyale g = new PlinkoRoyale(address(ht), feeRecipient, address(w));
        ht.mint(alice, 100_000_000e18);
        ht.mint(bob, 100_000_000e18);
        vm.prank(alice);
        ht.approve(address(g), type(uint256).max);
        vm.prank(bob);
        ht.approve(address(g), type(uint256).max);

        (uint256 roundId,,) = g.currentRound();
        vm.prank(alice);
        g.enter(roundId, TIER1, bytes32(0));
        vm.prank(bob);
        g.enter(roundId, TIER1, bytes32(0));
        _closeAndDraw(g, w);
        _fulfill(w, WORD);

        ht.setBlocked(g.DEAD_ADDRESS(), true);
        vm.expectRevert("recipient blocked");
        g.settle(roundId);

        ht.setBlocked(g.DEAD_ADDRESS(), false);
        g.settle(roundId);
        assertGt(ht.balanceOf(g.DEAD_ADDRESS()), 0);
    }

    // --- VRF edges -----------------------------------------------------

    /// @notice Wrapper returns requestId 0: the word can never be stored,
    ///         but stakes are recoverable via the random-timeout refund.
    function testZeroRequestIdRecovery() public {
        ZeroIdWrapper zw = new ZeroIdWrapper();
        PlinkoRoyale g = new PlinkoRoyale(address(agc), feeRecipient, address(zw));
        vm.prank(alice);
        agc.approve(address(g), type(uint256).max);
        vm.prank(bob);
        agc.approve(address(g), type(uint256).max);

        (uint256 roundId,, uint64 closesAt) = g.currentRound();
        vm.prank(alice);
        g.enter(roundId, TIER1, bytes32(0));
        vm.prank(bob);
        g.enter(roundId, TIER1, bytes32(0));

        vm.warp(uint256(closesAt) + 1);
        vm.prank(keeper);
        g.draw{value: 0.001 ether}(roundId); // stores requestId 0

        vm.expectRevert("unknown request");
        zw.fulfillZero(address(g));

        vm.warp(block.timestamp + 1 hours + 1);
        g.refund(roundId);
        assertEq(g.balanceOf(alice), TIER1);
        assertEq(g.balanceOf(bob), TIER1);
    }

    /// @notice A VRF word of exactly 0 is accepted (wordSet flag) and the
    ///         round settles normally.
    function testWordZeroSettles() public {
        _enter(alice, TIER1);
        _enter(bob, TIER2);
        uint256 roundId = _closeAndDraw(game, wrapper);
        _fulfill(wrapper, 0);
        assertEq(game.randomWordOf(roundId), 0);
        game.settle(roundId);
        (uint8 phase,,,,,,,,) = game.roundDetail(roundId);
        assertEq(phase, 3);
        uint256 pot = TIER1 + TIER2;
        (, , , , , , uint256 burned, uint256 feePaid, uint256 dust) = game.roundDetail(roundId);
        assertEq(burned, (pot * 30) / 10_000);
        assertEq(feePaid, (pot * 30) / 10_000);
        assertEq(game.balanceOf(alice) + game.balanceOf(bob) + burned + feePaid + dust, pot);
        assertLt(dust, 2); // flooring bound: dust < players
    }

    /// @notice Callback with an unregistered requestId reverts even when
    ///         called by the wrapper address.
    function testBogusRequestIdReverts() public {
        _enter(alice, TIER1);
        _enter(bob, TIER1);
        _closeAndDraw(game, wrapper);
        uint256[] memory words = new uint256[](1);
        words[0] = 7;
        vm.prank(address(wrapper));
        vm.expectRevert("unknown request");
        game.rawFulfillRandomWords(999_999, words);
    }

    /// @notice Double fulfillment of the same request reverts.
    function testDoubleFulfillReverts() public {
        _enter(alice, TIER1);
        _enter(bob, TIER1);
        _closeAndDraw(game, wrapper);
        uint256 requestId = wrapper.nextRequestId() - 1;
        wrapper.fulfill(requestId, WORD);
        vm.expectRevert("word already set");
        wrapper.fulfill(requestId, WORD + 1);
    }

    // --- timing boundaries ----------------------------------------------

    /// @notice Exact boundary behavior at closesAt and at the timeouts.
    function testBoundaryTimestamps() public {
        (uint256 roundId,, uint64 closesAt) = game.currentRound();

        // Last second of the window: entry still works.
        vm.warp(uint256(closesAt) - 1);
        vm.prank(alice);
        game.enter(roundId, TIER1, bytes32(0));
        vm.prank(bob);
        game.enter(roundId, TIER1, bytes32(0));

        // At closesAt exactly: round has flipped; old round rejects entry,
        // and draw still reverts (needs strictly greater than closesAt).
        vm.warp(uint256(closesAt));
        vm.prank(carol);
        vm.expectRevert("round not open");
        game.enter(roundId, TIER1, bytes32(0));
        vm.prank(keeper);
        vm.expectRevert("round still open");
        game.draw{value: 1 ether}(roundId);

        // One second later draw works.
        vm.warp(uint256(closesAt) + 1);
        uint256 fee = game.drawFee(1 gwei);
        vm.prank(keeper);
        game.draw{value: fee}(roundId);
    }

    /// @notice Refund timeout boundary: exactly at closesAt+1h still
    ///         reverts; one second later it succeeds.
    function testRefundTimeoutBoundary() public {
        _enter(alice, TIER1);
        _enter(bob, TIER1);
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1 hours);
        vm.expectRevert("refund not available yet");
        game.refund(roundId);
        vm.warp(uint256(closesAt) + 1 hours + 1);
        game.refund(roundId);
        assertEq(game.balanceOf(alice), TIER1);
    }

    // --- keeper / permissionlessness -------------------------------------

    /// @notice A contract keeper without receive() cannot draw with excess
    ///         value (refund fails) but can draw with the exact fee.
    function testNoReceiveKeeperDraw() public {
        _enter(alice, TIER1);
        _enter(bob, TIER1);
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        vm.warp(uint256(closesAt) + 1);

        NoReceiveKeeper nk = new NoReceiveKeeper();
        vm.deal(address(nk), 10 ether);
        uint256 fee = game.drawFee(1 gwei);

        vm.expectRevert("fee refund failed");
        nk.doDraw{value: fee + 1 ether}(game, roundId);

        nk.doDraw{value: fee}(game, roundId); // exact fee: no refund needed
        (uint8 phase,,,,,,,,) = game.roundDetail(roundId);
        assertEq(phase, 2);
    }

    /// @notice settle() and refund() are truly permissionless.
    function testThirdPartySettleAndRefund() public {
        _enter(alice, TIER1);
        _enter(bob, TIER1);
        uint256 roundId = _closeAndDraw(game, wrapper);
        _fulfill(wrapper, WORD);
        vm.prank(stranger);
        game.settle(roundId);
        assertGt(game.balanceOf(alice), 0);

        // Next round: single player, stranger refunds after close.
        (uint256 r2,, uint64 closesAt2) = game.currentRound();
        vm.prank(carol);
        game.enter(r2, TIER1, bytes32(0));
        vm.warp(uint256(closesAt2) + 1);
        vm.prank(stranger);
        game.refund(r2);
        assertEq(game.balanceOf(carol), TIER1);
    }

    // --- multi-round independence -----------------------------------------

    /// @notice Two rounds in flight settle independently, out of order.
    function testMultiRoundIndependence() public {
        // Round 0: alice + bob.
        _enter(alice, TIER1);
        _enter(bob, TIER1);
        (uint256 r0,, uint64 closes0) = game.currentRound();
        vm.warp(uint256(closes0) + 1);
        uint256 fee = game.drawFee(1 gwei);
        vm.prank(keeper);
        game.draw{value: fee}(r0);
        uint256 req0 = wrapper.nextRequestId() - 1;

        // Round 1: alice + carol (alice plays both rounds).
        (uint256 r1,, uint64 closes1) = game.currentRound();
        assertEq(r1, r0 + 1);
        vm.prank(alice);
        game.enter(r1, TIER2, bytes32(0));
        vm.prank(carol);
        game.enter(r1, TIER2, bytes32(0));
        assertEq(game.stakedOf(alice), TIER1 + TIER2);

        vm.warp(uint256(closes1) + 1);
        vm.prank(keeper);
        game.draw{value: fee}(r1);
        uint256 req1 = wrapper.nextRequestId() - 1;

        // Settle round 1 first.
        wrapper.fulfill(req1, WORD + 1);
        game.settle(r1);
        assertEq(game.stakedOf(alice), TIER1);
        (, uint256 payoutA1,) = game.result(r1, alice);
        assertEq(game.balanceOf(alice), payoutA1);

        // Then round 0.
        wrapper.fulfill(req0, WORD);
        game.settle(r0);
        assertEq(game.stakedOf(alice), 0);
        (, uint256 payoutA0,) = game.result(r0, alice);
        assertEq(game.balanceOf(alice), payoutA0 + payoutA1);
    }

    // --- settle/refund gas bound (the lockup finding) ----------------------

    function _bigRound(uint256 n, bool doSettle) internal returns (uint256 gasUsed) {
        (uint256 roundId,, uint64 closesAt) = game.currentRound();
        for (uint256 i = 0; i < n; i++) {
            address p = address(uint160(0x30000 + i));
            agc.mint(p, TIER1);
            vm.startPrank(p);
            agc.approve(address(game), TIER1);
            game.enter(roundId, TIER1, bytes32(i));
            vm.stopPrank();
        }
        vm.warp(uint256(closesAt) + 1);
        if (doSettle) {
            uint256 fee = game.drawFee(1 gwei);
            vm.prank(keeper);
            game.draw{value: fee}(roundId);
            _fulfill(wrapper, WORD);
            uint256 g0 = gasleft();
            game.settle(roundId);
            gasUsed = g0 - gasleft();
        } else {
            vm.warp(uint256(closesAt) + 1 hours + 1);
            uint256 g0 = gasleft();
            game.refund(roundId);
            gasUsed = g0 - gasleft();
        }
    }

    /// @notice Measures settle gas at 1,000 players. Extrapolation gives
    ///         the hard player cap imposed by the block gas limit; beyond
    ///         it, settle can never execute and (post-word) refund is
    ///         blocked -> permanent lockup. This is the audit's main
    ///         scalability finding; the numbers below are the evidence.
    function testSettleGas1000Players() public {
        // With MAX_PLAYERS = 500 (audit M-1 fix), a full round settles well
        // under a 30M-gas block. This test now measures the cap.
        uint256 settleGas = _bigRound(500, true);
        console2.log("settle gas, 500 players (cap):", settleGas);
        console2.log("per player:", settleGas / 500);
        assertLt(settleGas, 30_000_000);
    }

    function testRefundGas1000Players() public {
        // With MAX_PLAYERS = 500 (audit M-1 fix), a full round refunds well
        // under a 30M-gas block. This test now measures the cap.
        uint256 refundGas = _bigRound(500, false);
        console2.log("refund gas, 500 players (cap):", refundGas);
        console2.log("per player:", refundGas / 500);
        assertLt(refundGas, 30_000_000);
    }
}
