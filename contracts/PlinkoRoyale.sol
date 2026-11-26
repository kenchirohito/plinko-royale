// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Plinko Royale
/// @notice A PvP Plinko game for the AGC (Agentic Coin) ecosystem, modeled on
///         AGC Battle Royale's pattern: players pay each other from a shared
///         pot, so the contract never needs a bankroll.
/// @dev Trust model (read this first):
///      - No owner, no admin, no pause, no upgradeability, no setters.
///        Every parameter is a constant or an immutable set once in the
///        constructor. Nobody — including the deployer — can change the
///        rules, move player funds, or stop the game after deployment.
///      - Randomness comes from Chainlink VRF v2.5 (direct funding wrapper),
///        one word per round. The VRF proof is verified by Chainlink's
///        coordinator/wrapper before the word reaches this contract, and
///        entries close before the word exists, so nobody knows or can
///        influence a round's outcome in advance.
///      - Settlement math is integer-only and identical to the reference
///        implementation in verify.py: 0.3% of the pot is burned, 0.3% goes
///        to an immutable fee recipient, and the remaining 99.4% is split
///        proportionally to score (stake x slot multiplier).
///      - Rounds run on a fixed 5-minute time grid starting at deployment.
///        Round 0 opens at the deployment timestamp; round N opens at
///        genesis + N * 60 seconds. No keeper is needed to start rounds.
/// @dev Assumptions an auditor should check:
///      - The stake token (AGC) is a standard ERC20 that returns bool from
///        transfer/transferFrom and does not tax transfers to or from this
///        contract (the same assumption Battle Royale makes). enter()
///        verifies the exact amount received and reverts otherwise, so a
///        taxed transfer can never corrupt the accounting.
///      - block.timestamp is used for round boundaries and timeouts.
///        Validator timestamp drift on BSC is a few seconds, which is
///        immaterial against 5-minute rounds and 1-hour timeouts.

/// @notice Minimal ERC20 interface — only the functions this contract calls.
/// @dev Defined inline so the file has zero external imports.
interface IERC20 {
    /// @notice Returns the token balance of an account.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Moves tokens from the caller to a recipient.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Moves tokens from one account to another using an allowance.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Minimal Chainlink VRF v2.5 wrapper interface (direct funding,
///         native-currency payment) — only the functions this contract calls.
/// @dev Signatures verified against Chainlink's VRFV2PlusWrapper
///      (contracts-v1.3.0). Defined inline so the file has zero imports.
interface IVRFV2PlusWrapper {
    /// @notice Quotes the native-currency price of a VRF request at the
    ///         current transaction gas price.
    /// @param _callbackGasLimit Gas limit reserved for the callback.
    /// @param _numWords Number of random words to request.
    /// @return The price in wei of the native currency (BNB on BSC).
    function calculateRequestPriceNative(uint32 _callbackGasLimit, uint32 _numWords)
        external
        view
        returns (uint256);

    /// @notice Estimates the native-currency price of a VRF request at a
    ///         caller-supplied gas price (for off-chain fee quotes).
    /// @param _callbackGasLimit Gas limit reserved for the callback.
    /// @param _numWords Number of random words to request.
    /// @param _requestGasPriceWei Gas price in wei to price the request at.
    /// @return The estimated price in wei of the native currency.
    function estimateRequestPriceNative(uint32 _callbackGasLimit, uint32 _numWords, uint256 _requestGasPriceWei)
        external
        view
        returns (uint256);

    /// @notice Requests random words, paid in the native currency.
    /// @dev The wrapper requires msg.value >= its quoted price and calls
    ///      rawFulfillRandomWords(requestId, words) on the caller later,
    ///      with exactly _callbackGasLimit gas.
    /// @param _callbackGasLimit Gas limit reserved for the callback.
    /// @param _requestConfirmations Blocks to wait before fulfilling.
    /// @param _numWords Number of random words to request.
    /// @param extraArgs Must encode native payment (see _extraArgsNative).
    /// @return requestId The VRF request identifier.
    function requestRandomWordsInNative(
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        bytes calldata extraArgs
    ) external payable returns (uint256 requestId);
}

/// @title Plinko Royale game contract
/// @notice See the file header for the trust model. In short: stake a fixed
///         tier, one ball per player per round, pot split by score.
contract PlinkoRoyale {
    // ------------------------------------------------------------------
    // Constants (game rules — fixed forever, no setters exist)
    // ------------------------------------------------------------------

    /// @notice Length of one round's entry window, in seconds (5 minutes).
    uint256 public constant ROUND_DURATION = 60;

    /// @notice How long after a round closes anyone may still draw before
    ///         the round becomes refundable (1 hour, mirrors Battle Royale).
    uint256 public constant DRAW_TIMEOUT = 1 hours;

    /// @notice How long after a draw request the VRF word may still arrive
    ///         before the round becomes refundable (1 hour).
    uint256 public constant RANDOM_TIMEOUT = 1 hours;

    /// @notice Smallest stake tier: 100,000 AGC (AGC has 18 decimals).
    ///         The seven tiers mirror AGC Battle Royale's stake ladder.
    uint256 public constant TIER_1 = 100_000e18;

    /// @notice Stake tier: 300,000 AGC.
    uint256 public constant TIER_2 = 300_000e18;

    /// @notice Stake tier: 500,000 AGC.
    uint256 public constant TIER_3 = 500_000e18;

    /// @notice Stake tier: 1,000,000 AGC.
    uint256 public constant TIER_4 = 1_000_000e18;

    /// @notice Stake tier: 2,000,000 AGC.
    uint256 public constant TIER_5 = 2_000_000e18;

    /// @notice Stake tier: 5,000,000 AGC.
    uint256 public constant TIER_6 = 5_000_000e18;

    /// @notice Largest stake tier: 10,000,000 AGC.
    uint256 public constant TIER_7 = 10_000_000e18;

    /// @notice Burn share of every settled pot, in basis points (30 = 0.3%).
    uint256 public constant BURN_BPS = 30;

    /// @notice Fee share of every settled pot, in basis points (30 = 0.3%).
    uint256 public constant FEE_BPS = 30;

    /// @notice Basis-point denominator (10000 = 100%).
    uint256 public constant BPS_DEN = 10_000;

    /// @notice Address the burn share is sent to (the conventional dead
    ///         address; tokens sent there are effectively destroyed).
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @notice Gas reserved for the VRF callback. The callback only stores
    ///         one word and emits an event, so 100k is comfortable headroom.
    ///         The VRF price scales with this number, so it is kept small.
    uint32 public constant CALLBACK_GAS_LIMIT = 100_000;

    /// @notice Blocks the VRF oracle waits before fulfilling. BSC's minimum
    ///         is 3; using the minimum keeps rounds fast.
    uint16 public constant REQUEST_CONFIRMATIONS = 3;

    /// @notice Random words requested per round: exactly one. Every player's
    ///         slot is derived from this single word (see _slotOf).
    uint32 public constant NUM_WORDS = 1;

    /// @notice Maximum entries per round. settle() and refund() loop over
    ///         every player in one transaction, so an unbounded round could
    ///         exceed the block gas limit and lock its pot forever (audit
    ///         finding M-1). Measured cost is ~37.5k gas/player for settle
    ///         and ~32.2k for refund, so 500 players (~18.7M / ~16.1M gas)
    ///         stays far below even a 30M-gas block.
    uint256 public constant MAX_PLAYERS = 500;

    /// @notice Tag prefixing Chainlink's ExtraArgsV1 encoding:
    ///         the first 4 bytes of keccak256("VRF ExtraArgsV1").
    bytes4 internal constant EXTRA_ARGS_V1_TAG = 0x92fd1338;

    // ------------------------------------------------------------------
    // Immutables (set once in the constructor, never changeable)
    // ------------------------------------------------------------------

    /// @notice The stake token (AGC).
    IERC20 public immutable token;

    /// @notice Address that receives the 0.3% fee from every settled round.
    /// @dev Immutable by design: the fee funds operations (e.g. the VRF
    ///      keeper's BNB costs) but nobody can redirect it after deployment.
    address public immutable feeRecipient;

    /// @notice The Chainlink VRF v2.5 wrapper used for randomness.
    IVRFV2PlusWrapper public immutable wrapper;

    /// @notice Deployment timestamp. Round 0 opens at this moment and a new
    ///         round opens every ROUND_DURATION seconds after it.
    uint256 public immutable genesis;

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------

    /// @notice Stored round phase. Note: "AwaitingDraw" from the design doc
    ///         is not stored — it is derived in roundDetail() as "stored
    ///         phase is Open and the entry window has ended". Storing it
    ///         would need an extra transaction to flip the flag; deriving
    ///         it from the clock is exact and free.
    enum Phase {
        Open, // entries accepted (until closesAt), then awaiting draw
        AwaitingRandom, // draw requested, waiting for the VRF word
        Settled, // payouts credited, burn + fee taken (final)
        Refunded // every stake returned in full (final)
    }

    /// @notice One player's entry in one round.
    /// @dev stake == 0 means "no entry" (all tiers are > 0). The player's
    ///      slot and payout are NOT stored: they are pure functions of the
    ///      round's word, payoutPool and totalScore, so entryOf()/result()
    ///      recompute them in views. That saves two storage writes per
    ///      player at settlement (the dominant gas cost) with identical
    ///      results, since the recomputation is deterministic.
    struct Entry {
        uint256 stake;
        bytes32 clientSeed;
    }

    /// @notice One round's bookkeeping.
    /// @dev opensAt/closesAt are derived from the round id (see _opensAt),
    ///      so they are not stored.
    struct Round {
        Phase phase;
        uint256 totalStaked;
        uint256 requestId;
        uint256 drawRequestedAt;
        uint256 word;
        bool wordSet;
        uint256 payoutPool; // set at settlement; lets views recompute payouts
        uint256 totalScore; // set at settlement; lets views recompute payouts
        uint256 burned;
        uint256 feePaid;
        uint256 dust;
        address[] players;
    }

    /// @dev All rounds by id. A fresh round id reads as phase Open with
    ///      zero totals, which is exactly a new round's state.
    mapping(uint256 => Round) internal _rounds;

    /// @dev Entries by round id, then player.
    mapping(uint256 => mapping(address => Entry)) internal _entries;

    /// @dev VRF request id -> round id, so the callback can find its round.
    mapping(uint256 => uint256) internal _requestToRound;

    /// @dev In-game balances (payouts and refunds land here; players pull
    ///      them out with withdraw()).
    mapping(address => uint256) internal _balances;

    /// @dev Total stake each player currently has in non-final rounds.
    ///      Increased on enter, decreased on settle/refund. Together with
    ///      _balances and accumulated dust this always equals the tokens
    ///      held by the contract.
    mapping(address => uint256) internal _staked;

    /// @dev Reentrancy lock: 1 = unlocked, 2 = locked.
    uint256 internal _lock;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    /// @notice A player entered a round.
    /// @dev The design sketch also had an `agent` flag here (Agent ID holder
    ///      or not, as in Battle Royale). It is deliberately not computed
    ///      on-chain: deriving it trustlessly would need an external registry
    ///      call inside enter(), adding a failure mode to the game's most
    ///      basic function. Indexers and frontends can join this event with
    ///      Agent ID registry data off-chain instead. Rules and payouts are
    ///      identical for agents and humans either way.
    event Entered(uint256 indexed roundId, address indexed player, uint256 amount, bytes32 clientSeed);

    /// @notice A VRF draw was requested for a round.
    event DrawRequested(uint256 indexed roundId, uint256 requestId);

    /// @notice The VRF word for a round arrived. Anyone can recompute every
    ///         player's slot from (word, roundId, player, clientSeed).
    event RandomFulfilled(uint256 indexed roundId, uint256 word);

    /// @notice A round settled: payouts credited, burn + fee taken.
    /// @dev Invariant: sum(payouts) + burned + feePaid + dust == pot.
    event Settled(uint256 indexed roundId, uint256 pot, uint256 burned, uint256 feePaid, uint256 dust);

    /// @notice A round was refunded in full (no burn, no fee).
    event Refunded(uint256 indexed roundId, uint256 pot);

    /// @notice A player withdrew in-game balance to their wallet.
    event Withdrawn(address indexed player, uint256 amount);

    // ------------------------------------------------------------------
    // Construction
    // ------------------------------------------------------------------

    /// @notice Deploys the game. All three addresses are immutable.
    /// @param token_ The stake token (AGC ERC20).
    /// @param feeRecipient_ Address that receives the 0.3% fee per round.
    /// @param wrapper_ The Chainlink VRF v2.5 wrapper for this chain.
    constructor(address token_, address feeRecipient_, address wrapper_) {
        require(token_ != address(0), "token is zero address");
        require(feeRecipient_ != address(0), "fee recipient is zero address");
        require(wrapper_ != address(0), "wrapper is zero address");
        token = IERC20(token_);
        feeRecipient = feeRecipient_;
        wrapper = IVRFV2PlusWrapper(wrapper_);
        genesis = block.timestamp;
        _lock = 1;
    }

    /// @notice Reentrancy guard for functions that make external calls.
    modifier nonReentrant() {
        require(_lock == 1, "reentrant call");
        _lock = 2;
        _;
        _lock = 1;
    }

    // ------------------------------------------------------------------
    // Constant views (interface compatibility with the design sketch)
    // ------------------------------------------------------------------

    /// @notice The seven allowed stake amounts, in token wei.
    function stakeTiers() external pure returns (uint256[7] memory) {
        return [TIER_1, TIER_2, TIER_3, TIER_4, TIER_5, TIER_6, TIER_7];
    }

    /// @notice Slot multipliers scaled x100, slots 0..8 (edges high,
    ///         center low). Expected value is exactly 1.0: with slot
    ///         probabilities C(8,k)/256, sum(C(8,k) * mult[k]) = 25,600
    ///         = 256 * 100. The minimum (40) is > 0, which guarantees the
    ///         settlement denominator can never be zero.
    function multipliersX100() public pure returns (uint16[9] memory) {
        return [uint16(1160), 300, 140, 70, 40, 70, 140, 300, 1160];
    }

    /// @notice Burn share in basis points (30 = 0.3%).
    function burnBps() external pure returns (uint256) {
        return BURN_BPS;
    }

    /// @notice Fee share in basis points (30 = 0.3%).
    function feeBps() external pure returns (uint256) {
        return FEE_BPS;
    }

    /// @notice The dead address the burn share is sent to.
    function deadAddress() external pure returns (address) {
        return DEAD_ADDRESS;
    }

    // ------------------------------------------------------------------
    // Round timing (fixed grid from genesis — no keeper needed)
    // ------------------------------------------------------------------

    /// @notice The round that is open right now.
    /// @return id The current round id.
    /// @return opensAt When the current round opened (unix seconds).
    /// @return closesAt When entries close (unix seconds).
    function currentRound() external view returns (uint256 id, uint64 opensAt, uint64 closesAt) {
        id = _currentRoundId();
        opensAt = uint64(_opensAt(id));
        closesAt = uint64(_closesAt(id));
    }

    /// @notice Full public state of one round.
    /// @dev The reported phase uses the design doc's numbering:
    ///      0 Open, 1 AwaitingDraw, 2 AwaitingRandom, 3 Settled, 4 Refunded.
    ///      AwaitingDraw is derived: stored phase Open + window ended.
    /// @param roundId The round to read.
    /// @return phase Effective phase (0..4 as above).
    /// @return opensAt When the round opened (unix seconds).
    /// @return closesAt When entries closed/close (unix seconds).
    /// @return totalStaked Sum of all stakes in the round.
    /// @return playerCount Number of entries in the round.
    /// @return requestId VRF request id (0 until drawn).
    /// @return burned Amount burned at settlement (0 until settled).
    /// @return feePaid Amount paid to the fee recipient (0 until settled).
    /// @return dust Flooring residue left in the contract (0 until settled).
    function roundDetail(uint256 roundId)
        external
        view
        returns (
            uint8 phase,
            uint64 opensAt,
            uint64 closesAt,
            uint256 totalStaked,
            uint256 playerCount,
            uint256 requestId,
            uint256 burned,
            uint256 feePaid,
            uint256 dust
        )
    {
        Round storage r = _rounds[roundId];
        opensAt = uint64(_opensAt(roundId));
        closesAt = uint64(_closesAt(roundId));
        if (r.phase == Phase.Open) {
            phase = block.timestamp >= closesAt ? 1 : 0;
        } else if (r.phase == Phase.AwaitingRandom) {
            phase = 2;
        } else if (r.phase == Phase.Settled) {
            phase = 3;
        } else {
            phase = 4;
        }
        totalStaked = r.totalStaked;
        playerCount = r.players.length;
        requestId = r.requestId;
        burned = r.burned;
        feePaid = r.feePaid;
        dust = r.dust;
    }

    /// @notice The VRF word of a round (0 until fulfilled). Public so anyone
    ///         can recompute every slot and verify settlement.
    /// @param roundId The round to read.
    function randomWordOf(uint256 roundId) external view returns (uint256) {
        return _rounds[roundId].word;
    }

    /// @notice Whether the VRF word of a round has been fulfilled.
    /// @dev Distinct from `randomWordOf(roundId) != 0`: the fulfilled word
    ///      could in principle be exactly 0 (probability 2^-256), in which
    ///      case the round is still settleable. UIs and agents should gate
    ///      settle() on this flag, not on the word value.
    /// @param roundId The round to read.
    function wordReceivedOf(uint256 roundId) external view returns (bool) {
        return _rounds[roundId].wordSet;
    }

    /// @notice When draw() was requested for a round (0 until drawn).
    /// @dev Lets UIs and agents compute the exact refund moment for the
    ///      AwaitingRandom phase: refund() opens at
    ///      drawRequestedAtOf(roundId) + RANDOM_TIMEOUT.
    /// @param roundId The round to read.
    function drawRequestedAtOf(uint256 roundId) external view returns (uint256) {
        return _rounds[roundId].drawRequestedAt;
    }

    /// @notice The players who entered a round, in entry order.
    /// @dev Audit finding L-6: agents and UIs previously had to reconstruct
    ///      this list from Entered events via eth_getLogs, which some RPCs
    ///      refuse to serve. This view makes the list readable with a plain
    ///      eth_call. The array is bounded by MAX_PLAYERS (500), so the
    ///      response size is capped. Returns an empty array for rounds with
    ///      no entries (including rounds that do not exist yet).
    /// @param roundId The round to read.
    function playersOf(uint256 roundId) external view returns (address[] memory) {
        return _rounds[roundId].players;
    }

    /// @notice One player's entry in one round.
    /// @dev slot and payout are recomputed from the round's word (they are
    ///      0 until the round is settled). stake == 0 means the player did
    ///      not enter.
    function entryOf(uint256 roundId, address player)
        external
        view
        returns (uint256 stake, bytes32 clientSeed, uint8 slot, uint256 payout)
    {
        Entry storage e = _entries[roundId][player];
        (slot, payout) = _slotAndPayout(roundId, player);
        return (e.stake, e.clientSeed, slot, payout);
    }

    /// @notice A player's withdrawable in-game balance.
    function balanceOf(address player) external view returns (uint256) {
        return _balances[player];
    }

    /// @notice A player's total stake currently locked in non-final rounds.
    function stakedOf(address player) external view returns (uint256) {
        return _staked[player];
    }

    /// @notice A player's result in one round (audit view).
    /// @dev payout and slot are recomputed from the round's word (0 until
    ///      the round is settled). For a refunded round, payout stays 0 and
    ///      the stake was credited to balanceOf.
    /// @return staked The player's stake (0 if they did not enter).
    /// @return payout The player's credited payout (settled rounds only).
    /// @return slot The player's landing slot 0..8 (settled rounds only).
    function result(uint256 roundId, address player)
        external
        view
        returns (uint256 staked, uint256 payout, uint8 slot)
    {
        Entry storage e = _entries[roundId][player];
        (slot, payout) = _slotAndPayout(roundId, player);
        return (e.stake, payout, slot);
    }

    /// @notice Quotes the BNB fee a draw() call must carry at a given gas
    ///         price, mirroring Battle Royale's drawFee.
    /// @dev Keepers read this off-chain, then send draw() with at least this
    ///      much BNB. draw() refunds any excess in the same transaction.
    /// @param gasPriceWei Gas price in wei to price the request at.
    /// @return The estimated VRF fee in wei of BNB.
    function drawFee(uint256 gasPriceWei) external view returns (uint256) {
        return wrapper.estimateRequestPriceNative(CALLBACK_GAS_LIMIT, NUM_WORDS, gasPriceWei);
    }

    // ------------------------------------------------------------------
    // Gameplay
    // ------------------------------------------------------------------

    /// @notice Enters the current round with one fixed-tier stake.
    /// @dev One entry per address per round. The stake is pulled from the
    ///      caller's wallet via transferFrom (approve first). The exact
    ///      received amount is verified, so a fee-on-transfer token would
    ///      revert here instead of corrupting the accounting.
    ///      Note: the design doc (§6) mentioned taking the stake from
    ///      in-game balance first, like Battle Royale. This contract
    ///      deliberately pulls from the wallet only — one code path, less
    ///      to audit. Players withdraw winnings first if they want to
    ///      re-stake them.
    /// @param roundId Must be the currently open round (see currentRound).
    /// @param amount Must be exactly one of the seven stake tiers.
    /// @param clientSeed Optional player entropy (bytes32(0) if unused).
    ///        It cannot bias the outcome: the VRF word is unknown to
    ///        everyone until after entries close.
    function enter(uint256 roundId, uint256 amount, bytes32 clientSeed) external nonReentrant {
        require(roundId == _currentRoundId(), "round not open");
        require(
            amount == TIER_1 || amount == TIER_2 || amount == TIER_3 || amount == TIER_4 || amount == TIER_5
                || amount == TIER_6 || amount == TIER_7,
            "amount not a stake tier"
        );
        Round storage r = _rounds[roundId];
        require(r.phase == Phase.Open, "round not open");
        require(r.players.length < MAX_PLAYERS, "round full");
        Entry storage e = _entries[roundId][msg.sender];
        require(e.stake == 0, "already entered");

        // Effects first (checks-effects-interactions): if the transfer
        // below fails, the whole transaction reverts and these roll back.
        e.stake = amount;
        e.clientSeed = clientSeed;
        r.players.push(msg.sender);
        r.totalStaked += amount;
        _staked[msg.sender] += amount;

        // Interaction: pull the stake and verify the exact amount arrived.
        uint256 balanceBefore = token.balanceOf(address(this));
        require(token.transferFrom(msg.sender, address(this), amount), "stake transfer failed");
        require(token.balanceOf(address(this)) - balanceBefore == amount, "stake transfer taxed");

        emit Entered(roundId, msg.sender, amount, clientSeed);
    }

    /// @notice Requests the VRF draw for a closed round. Anyone may call
    ///         this (normally the project keeper does, seconds after close).
    /// @dev The caller pays the VRF fee in BNB: send at least drawFee(gas
    ///      price). The exact price is forwarded to the wrapper and any
    ///      excess is refunded to the caller in the same transaction, so
    ///      the caller must be able to receive BNB (an EOA, or a contract
    ///      with a receive function). Nobody is paid for drawing.
    ///      Rounds with fewer than 2 players cannot be drawn — use refund().
    /// @param roundId The closed round to draw.
    function draw(uint256 roundId) external payable nonReentrant {
        Round storage r = _rounds[roundId];
        require(r.phase == Phase.Open, "round not awaiting draw");
        require(block.timestamp > _closesAt(roundId), "round still open");
        require(r.players.length >= 2, "too few players, use refund");

        uint256 price = wrapper.calculateRequestPriceNative(CALLBACK_GAS_LIMIT, NUM_WORDS);
        require(msg.value >= price, "insufficient VRF fee");

        // Effects before the external call, so a reentrant draw() reverts.
        r.phase = Phase.AwaitingRandom;
        r.drawRequestedAt = block.timestamp;

        uint256 requestId = wrapper.requestRandomWordsInNative{value: price}(
            CALLBACK_GAS_LIMIT, REQUEST_CONFIRMATIONS, NUM_WORDS, _extraArgsNative()
        );
        r.requestId = requestId;
        _requestToRound[requestId] = roundId;

        // Refund the excess fee to the caller.
        uint256 excess = msg.value - price;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            require(ok, "fee refund failed");
        }

        emit DrawRequested(roundId, requestId);
    }

    /// @notice VRF callback. Only the wrapper may call this.
    /// @dev Stores the word and nothing else — settlement is a separate
    ///      permissionless call (settle), so this callback stays tiny and
    ///      always fits in CALLBACK_GAS_LIMIT. If the round was already
    ///      refunded (random timeout), this reverts and the wrapper logs a
    ///      failed fulfillment; the round stays refunded.
    /// @param requestId The VRF request id from draw().
    /// @param words The random words (exactly one).
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata words) external {
        require(msg.sender == address(wrapper), "only wrapper");
        require(requestId != 0, "unknown request");
        uint256 roundId = _requestToRound[requestId];
        Round storage r = _rounds[roundId];
        require(r.requestId == requestId, "unknown request");
        require(r.phase == Phase.AwaitingRandom, "round not awaiting random");
        require(!r.wordSet, "word already set");
        require(words.length == 1, "expected one word");

        r.word = words[0];
        r.wordSet = true;

        emit RandomFulfilled(roundId, words[0]);
    }

    /// @notice Settles a round whose VRF word has arrived. Anyone may call.
    /// @dev Settlement math (identical to verify.py):
    ///        pot        = sum of stakes
    ///        burn       = floor(pot * 30 / 10000)   (0.3%)
    ///        fee        = floor(pot * 30 / 10000)   (0.3%)
    ///        payoutPool = pot - burn - fee          (99.4%)
    ///        score_i    = stake_i * MULT[slot_i]
    ///        payout_i   = floor(payoutPool * score_i / sum(scores))
    ///        dust       = payoutPool - sum(payouts) (stays in contract)
    ///      Conservation: sum(payouts) + burn + fee + dust == pot, always.
    ///      Division by zero is impossible: every stake > 0 and every
    ///      multiplier > 0, and draw() already required >= 2 players.
    ///      Gas: settlement is a single loop crediting every player. It
    ///      costs roughly 37.5k gas per player (measured in tests; the
    ///      dominant cost is one balance storage write per player), so a
    ///      full 500-player round (MAX_PLAYERS) settles in ~18.7M gas,
    ///      far below BSC's block gas limit (~140M). Slots and
    ///      payouts are not stored per player — views recompute them from
    ///      the stored word, payoutPool and totalScore (see _slotAndPayout).
    ///      See CONTRACT.md for measured numbers.
    /// @param roundId The round to settle.
    function settle(uint256 roundId) external nonReentrant {
        Round storage r = _rounds[roundId];
        require(r.phase == Phase.AwaitingRandom, "round not awaiting random");
        require(r.wordSet, "word not received yet");

        uint256 playerCount = r.players.length;
        uint256 pot = r.totalStaked;
        uint256 burn = (pot * BURN_BPS) / BPS_DEN;
        uint256 fee = (pot * FEE_BPS) / BPS_DEN;
        uint256 payoutPool = pot - burn - fee;

        // First pass: derive every score and sum them.
        uint16[9] memory mult = multipliersX100();
        uint256[] memory scores = new uint256[](playerCount);
        uint256 totalScore = 0;
        for (uint256 i = 0; i < playerCount; i++) {
            address player = r.players[i];
            Entry storage e = _entries[roundId][player];
            uint8 slot = _slotOf(r.word, roundId, player, e.clientSeed);
            uint256 score = e.stake * uint256(mult[slot]);
            scores[i] = score;
            totalScore += score;
        }
        // totalScore > 0 by construction (stakes and multipliers are > 0).

        // Second pass: credit payouts to in-game balances (pull pattern).
        uint256 paidOut = 0;
        for (uint256 i = 0; i < playerCount; i++) {
            address player = r.players[i];
            Entry storage e = _entries[roundId][player];
            uint256 payout = (payoutPool * scores[i]) / totalScore;
            _balances[player] += payout;
            _staked[player] -= e.stake;
            paidOut += payout;
        }
        uint256 dust = payoutPool - paidOut;

        // Effects complete before any token transfer. payoutPool and
        // totalScore are stored so views can recompute each payout.
        r.phase = Phase.Settled;
        r.payoutPool = payoutPool;
        r.totalScore = totalScore;
        r.burned = burn;
        r.feePaid = fee;
        r.dust = dust;

        // Interactions last. If either transfer fails, everything reverts
        // and the round can be settled again later.
        require(token.transfer(DEAD_ADDRESS, burn), "burn transfer failed");
        require(token.transfer(feeRecipient, fee), "fee transfer failed");

        emit Settled(roundId, pot, burn, fee, dust);
    }

    /// @notice Refunds a round in full: every stake back to in-game
    ///         balances, no burn, no fee. Anyone may call once a refund
    ///         condition holds:
    ///         - fewer than 2 players entered (checked after close), or
    ///         - nobody drew within DRAW_TIMEOUT (1h) of close, or
    ///         - the VRF word never arrived within RANDOM_TIMEOUT (1h)
    ///           of the draw request.
    /// @dev A round whose word HAS arrived can never be refunded — settle()
    ///      is permissionless, so funds are never locked waiting for it.
    /// @param roundId The round to refund.
    function refund(uint256 roundId) external nonReentrant {
        Round storage r = _rounds[roundId];
        if (r.phase == Phase.Open) {
            require(block.timestamp > _closesAt(roundId), "round still open");
            require(
                r.players.length < 2 || block.timestamp > _closesAt(roundId) + DRAW_TIMEOUT,
                "refund not available yet"
            );
        } else if (r.phase == Phase.AwaitingRandom) {
            require(!r.wordSet, "word received, settle instead");
            require(block.timestamp > r.drawRequestedAt + RANDOM_TIMEOUT, "refund not available yet");
        } else {
            revert("round already final");
        }

        r.phase = Phase.Refunded;
        uint256 pot = r.totalStaked;
        for (uint256 i = 0; i < r.players.length; i++) {
            address player = r.players[i];
            uint256 stake = _entries[roundId][player].stake;
            _balances[player] += stake;
            _staked[player] -= stake;
        }

        emit Refunded(roundId, pot);
    }

    /// @notice Withdraws in-game balance to the caller's wallet.
    /// @dev Pull pattern: balance is debited before the transfer
    ///      (checks-effects-interactions) and the function is
    ///      reentrancy-guarded.
    /// @param amount Amount to withdraw, in token wei.
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "amount is zero");
        require(_balances[msg.sender] >= amount, "insufficient balance");

        _balances[msg.sender] -= amount;

        require(token.transfer(msg.sender, amount), "withdraw transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    // ------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------

    /// @notice Id of the round open at the current block time.
    function _currentRoundId() internal view returns (uint256) {
        return (block.timestamp - genesis) / ROUND_DURATION;
    }

    /// @notice Opening timestamp of a round.
    function _opensAt(uint256 roundId) internal view returns (uint256) {
        return genesis + roundId * ROUND_DURATION;
    }

    /// @notice Closing timestamp of a round (entries stop at this moment;
    ///         the next round opens at the same instant).
    function _closesAt(uint256 roundId) internal view returns (uint256) {
        return _opensAt(roundId) + ROUND_DURATION;
    }

    /// @notice Recomputes a player's slot and payout for a settled round.
    /// @dev Returns (0, 0) unless the round is Settled and the player
    ///      entered. The recomputation uses exactly the settle() formula
    ///      and the stored word/payoutPool/totalScore, so it always matches
    ///      the amount that was credited to the player's balance.
    function _slotAndPayout(uint256 roundId, address player) internal view returns (uint8 slot, uint256 payout) {
        Round storage r = _rounds[roundId];
        Entry storage e = _entries[roundId][player];
        if (r.phase != Phase.Settled || e.stake == 0) {
            return (0, 0);
        }
        slot = _slotOf(r.word, roundId, player, e.clientSeed);
        uint256 score = e.stake * uint256(multipliersX100()[slot]);
        payout = (r.payoutPool * score) / r.totalScore;
    }

    /// @notice Derives a player's landing slot from the round's VRF word.
    /// @dev Exact spec (DESIGN.md §5): take the first (most significant)
    ///      8 bits of keccak256(abi.encode(word, roundId, player,
    ///      clientSeed)) and count the 1-bits. Each bit is one peg bounce,
    ///      so the count follows the binomial distribution C(8,k)/256 —
    ///      identical to the physical board. The clientSeed is always
    ///      included in the hash (bytes32(0) when the player did not
    ///      supply one), keeping a single code path.
    /// @return slot The landing slot, 0..8.
    function _slotOf(uint256 word, uint256 roundId, address player, bytes32 clientSeed)
        internal
        pure
        returns (uint8 slot)
    {
        bytes32 hash = keccak256(abi.encode(word, roundId, player, clientSeed));
        uint8 pathBits = uint8(uint256(hash) >> 248);
        return _popcount8(pathBits);
    }

    /// @notice Counts the 1-bits in a byte (0..8). Plain loop on purpose:
    ///         eight iterations, no bit tricks, trivially auditable.
    function _popcount8(uint8 x) internal pure returns (uint8 count) {
        for (uint8 i = 0; i < 8; i++) {
            if (x & 1 == 1) {
                count++;
            }
            x >>= 1;
        }
    }

    /// @notice Builds Chainlink's ExtraArgsV1 encoding selecting native
    ///         (BNB) payment: the 4-byte tag followed by abi.encode(true).
    /// @dev The wrapper checks that byte 35 of extraArgs is 0x01 for
    ///      native payment; this encoding satisfies that.
    function _extraArgsNative() internal pure returns (bytes memory) {
        return abi.encodePacked(EXTRA_ARGS_V1_TAG, abi.encode(true));
    }
}
