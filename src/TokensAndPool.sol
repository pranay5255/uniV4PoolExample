// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "lib/v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title MockCbBTC - Mock Coinbase Wrapped BTC Token
/// @notice A simple ERC20 token for testing purposes on Base Sepolia
/// @dev 50% minted to deployer, 50% to partner address
contract MockCbBTC is ERC20 {
    uint8 private constant _DECIMALS = 8; // BTC uses 8 decimals

    // Partner address receives 50% of supply
    address constant PARTNER_ADDRESS = 0x4db8B3faF4F26c04d6E456e8D5A0c02941eb772e;

    constructor(uint256 initialSupply) ERC20("Coinbase Wrapped BTC", "cbBTC") {
        uint256 halfSupply = initialSupply / 2;
        // Mint 50% to deployer (msg.sender)
        _mint(msg.sender, halfSupply);
        // Mint 50% to partner address
        _mint(PARTNER_ADDRESS, initialSupply - halfSupply); // Use subtraction to handle odd numbers
    }

    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }
}

/// @title MockUSDC - Mock USD Coin Token
/// @notice A simple ERC20 token for testing purposes on Base Sepolia
/// @dev 50% minted to deployer, 50% to partner address
contract MockUSDC is ERC20 {
    uint8 private constant _DECIMALS = 6; // USDC uses 6 decimals

    // Partner address receives 50% of supply
    address constant PARTNER_ADDRESS = 0x4db8B3faF4F26c04d6E456e8D5A0c02941eb772e;

    constructor(uint256 initialSupply) ERC20("USD Coin", "USDC") {
        uint256 halfSupply = initialSupply / 2;
        // Mint 50% to deployer (msg.sender)
        _mint(msg.sender, halfSupply);
        // Mint 50% to partner address
        _mint(PARTNER_ADDRESS, initialSupply - halfSupply); // Use subtraction to handle odd numbers
    }

    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }
}
