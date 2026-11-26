// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice The callback interface the real wrapper calls on consumers.
interface IVRFConsumer {
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata words) external;
}

/// @title MockVRFWrapper
/// @notice Test stand-in for Chainlink's VRFV2PlusWrapper (direct funding,
///         native payment). Mimics the behaviors PlinkoRoyale depends on:
///         - quotes a fixed price via calculate/estimateRequestPriceNative,
///         - requires msg.value >= price in requestRandomWordsInNative,
///         - validates the native-payment extraArgs encoding the same way
///           the real wrapper does (36 bytes, byte 35 == 0x01),
///         - delivers words by calling rawFulfillRandomWords on the
///           consumer that made the request.
/// @dev Test-only. The fixed price stands in for the real wrapper's
///      gas-price-based pricing.
contract MockVRFWrapper {
    /// @notice Fixed request price in wei (stands in for dynamic pricing).
    uint256 public price = 0.001 ether;

    /// @notice Next request id to hand out (starts at 1, like the real one).
    uint256 public nextRequestId = 1;

    /// @notice Consumer that made each request.
    mapping(uint256 => address) public consumerOf;

    /// @notice Callback gas limit recorded for each request.
    mapping(uint256 => uint32) public callbackGasOf;

    /// @notice Sets the mock price (tests only).
    function setPrice(uint256 price_) external {
        price = price_;
    }

    /// @notice Quotes the request price (mock: the fixed price).
    function calculateRequestPriceNative(uint32, uint32) external view returns (uint256) {
        return price;
    }

    /// @notice Estimates the request price (mock: the fixed price).
    function estimateRequestPriceNative(uint32, uint32, uint256) external view returns (uint256) {
        return price;
    }

    /// @notice Records a randomness request, paid in native currency.
    function requestRandomWordsInNative(uint32 _callbackGasLimit, uint16, uint32 _numWords, bytes calldata extraArgs)
        external
        payable
        returns (uint256 requestId)
    {
        // Same native-payment encoding check as the real wrapper.
        require(extraArgs.length == 36, "bad extraArgs length");
        require(extraArgs[35] == 0x01, "extraArgs must select native payment");
        require(msg.value >= price, "fee too low");
        require(_numWords == 1, "mock serves one word");

        requestId = nextRequestId++;
        consumerOf[requestId] = msg.sender;
        callbackGasOf[requestId] = _callbackGasLimit;
        return requestId;
    }

    /// @notice Test helper: delivers a word to the consumer that requested it.
    /// @dev Calls with exactly the recorded callback gas limit, like the
    ///      real wrapper, so tests prove the callback fits its budget.
    function fulfill(uint256 requestId, uint256 word) external {
        address consumer = consumerOf[requestId];
        require(consumer != address(0), "unknown request");
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        IVRFConsumer(consumer).rawFulfillRandomWords{gas: callbackGasOf[requestId]}(requestId, words);
    }

    /// @notice Lets the mock hold BNB like the real wrapper does.
    receive() external payable {}
}
