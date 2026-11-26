// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title MockAGC
/// @notice Minimal ERC20 stand-in for AGC, for tests only.
/// @dev Standard ERC20 with 18 decimals and an open mint. An optional
///      transfer tax (taxBps, default 0) can be switched on by tests to
///      prove that PlinkoRoyale.enter() rejects taxed transfers instead of
///      corrupting its accounting. The tax is skimmed to a sink address.
contract MockAGC {
    string public name = "Mock Agentic Coin";
    string public symbol = "AGC";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    /// @notice Optional transfer tax in basis points (tests only).
    uint256 public taxBps;
    /// @notice Where the mock tax goes.
    address public taxSink = address(0xdead);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Mints new tokens (test faucet).
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @notice Sets the mock transfer tax (0 = standard ERC20 behavior).
    function setTaxBps(uint256 taxBps_) external {
        taxBps = taxBps_;
    }

    /// @notice Approves a spender.
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfers tokens from the caller.
    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfers tokens using an allowance.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance too low");
        allowance[from][msg.sender] = allowed - amount;
        _move(from, to, amount);
        return true;
    }

    /// @dev Moves tokens, skimming the optional mock tax.
    function _move(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance too low");
        balanceOf[from] -= amount;
        uint256 tax = (amount * taxBps) / 10_000;
        if (tax > 0) {
            balanceOf[taxSink] += tax;
            emit Transfer(from, taxSink, tax);
        }
        balanceOf[to] += amount - tax;
        emit Transfer(from, to, amount - tax);
    }
}
