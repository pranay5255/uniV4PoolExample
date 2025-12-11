// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {MockCbBTC, MockUSDC} from "../src/TokensAndPool.sol";

import {IPoolManager} from "lib/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "lib/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "lib/v4-core/src/types/PoolKey.sol";
import {Currency} from "lib/v4-core/src/types/Currency.sol";
import {IPositionManager} from "lib/v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "lib/v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {Actions} from "lib/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "lib/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {TickMath} from "lib/v4-core/src/libraries/TickMath.sol";
import {IERC20} from "lib/v4-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title DeployTokensAndInitializePool
/// @notice Deploys cbBTC and USDC mock tokens, then initializes a Uniswap v4 pool with initial liquidity
/// @dev Deploy to Base Sepolia using: 
///      forge script script/DeployTokenAndPool.sol --rpc-url https://sepolia.base.org --broadcast -vvvv
contract DeployTokensAndInitializePool is Script {
    // ============ Base Sepolia Uniswap v4 Addresses ============
    // From: https://docs.uniswap.org/contracts/v4/deployments
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant POSITION_MANAGER = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // ============ Token Configuration ============
    uint256 constant CBBTC_INITIAL_SUPPLY = 100 * 10 ** 8; // 100 cbBTC (8 decimals)
    uint256 constant USDC_INITIAL_SUPPLY = 10_000_000 * 10 ** 6; // 10M USDC (6 decimals)

    // ============ Pool Parameters ============
    // Fee tiers: 100 (0.01%), 500 (0.05%), 3000 (0.30%), 10000 (1.00%)
    uint24 constant SWAP_FEE = 3000; // 0.30% fee tier
    int24 constant TICK_SPACING = 60; // Standard tick spacing for 0.30% fee

    // Starting price: sqrtPriceX96 = sqrt(price) * 2^96
    // For 1:1 ratio: sqrt(1) * 2^96 = 79228162514264337593543950336
    uint160 constant SQRT_PRICE_X96 = 79228162514264337593543950336;

    // ============ Liquidity Parameters ============
    // Wide range: roughly -887220 to 887220 (full range for tick spacing 60)
    int24 constant TICK_LOWER = -887220; // Full range lower
    int24 constant TICK_UPPER = 887220;  // Full range upper
    
    // Amount of each token to provide as liquidity (50% of deployer's share)
    uint256 constant CBBTC_LIQUIDITY_AMOUNT = 25 * 10 ** 8; // 25 cbBTC
    uint256 constant USDC_LIQUIDITY_AMOUNT = 2_500_000 * 10 ** 6; // 2.5M USDC

    // ============ State Variables ============
    MockCbBTC public cbBTC;
    MockUSDC public usdc;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // ================================================================
        // STEP 1: Deploy Mock Tokens
        // ================================================================
        console2.log("=== Step 1: Deploying Mock Tokens ===");

        cbBTC = new MockCbBTC(CBBTC_INITIAL_SUPPLY);
        console2.log("MockCbBTC deployed at:", address(cbBTC));

        usdc = new MockUSDC(USDC_INITIAL_SUPPLY);
        console2.log("MockUSDC deployed at:", address(usdc));

        // ================================================================
        // STEP 2: Sort Tokens (Uniswap v4 requires currency0 < currency1)
        // ================================================================
        console2.log("\n=== Step 2: Sorting Tokens ===");

        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;

        if (address(cbBTC) < address(usdc)) {
            token0 = address(cbBTC);
            token1 = address(usdc);
            amount0 = CBBTC_LIQUIDITY_AMOUNT;
            amount1 = USDC_LIQUIDITY_AMOUNT;
            console2.log("Token order: cbBTC (token0) / USDC (token1)");
        } else {
            token0 = address(usdc);
            token1 = address(cbBTC);
            amount0 = USDC_LIQUIDITY_AMOUNT;
            amount1 = CBBTC_LIQUIDITY_AMOUNT;
            console2.log("Token order: USDC (token0) / cbBTC (token1)");
        }

        console2.log("Token0:", token0);
        console2.log("Token1:", token1);

        // ================================================================
        // STEP 3: Create Pool Key
        // ================================================================
        console2.log("\n=== Step 3: Creating Pool Key ===");

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: SWAP_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0)) // No hooks
        });

        console2.log("Pool Key created");
        console2.log("  - Fee:", SWAP_FEE);
        console2.log("  - Tick Spacing:", TICK_SPACING);

        // ================================================================
        // STEP 4: Initialize Pool via PoolManager
        // ================================================================
        console2.log("\n=== Step 4: Initializing Pool ===");

        IPoolManager poolManager = IPoolManager(POOL_MANAGER);
        int24 tick = poolManager.initialize(poolKey, SQRT_PRICE_X96);

        console2.log("Pool initialized!");
        console2.log("  - Initial Tick:", tick);
        console2.log("  - SqrtPriceX96:", SQRT_PRICE_X96);

        // ================================================================
        // STEP 5: Approve Tokens for Permit2
        // ================================================================
        console2.log("\n=== Step 5: Approving Tokens ===");

        // Approve Permit2 to spend tokens
        IERC20(token0).approve(PERMIT2, type(uint256).max);
        IERC20(token1).approve(PERMIT2, type(uint256).max);
        console2.log("Approved Permit2 for both tokens");

        // Approve PositionManager via Permit2
        IAllowanceTransfer(PERMIT2).approve(
            token0,
            POSITION_MANAGER,
            type(uint160).max,
            type(uint48).max
        );
        IAllowanceTransfer(PERMIT2).approve(
            token1,
            POSITION_MANAGER,
            type(uint160).max,
            type(uint48).max
        );
        console2.log("Approved PositionManager via Permit2");

        // ================================================================
        // STEP 6: Add Initial Liquidity via PositionManager
        // ================================================================
        console2.log("\n=== Step 6: Adding Initial Liquidity ===");

        IPositionManager positionManager = IPositionManager(POSITION_MANAGER);

        // Calculate liquidity from amounts
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            SQRT_PRICE_X96,
            TickMath.getSqrtPriceAtTick(TICK_LOWER),
            TickMath.getSqrtPriceAtTick(TICK_UPPER),
            amount0,
            amount1
        );

        console2.log("Calculated liquidity:", liquidity);

        // Encode the MINT_POSITION action
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        bytes[] memory params = new bytes[](2);
        
        // MINT_POSITION params: (poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData)
        params[0] = abi.encode(
            poolKey,
            TICK_LOWER,
            TICK_UPPER,
            liquidity,
            amount0 + (amount0 / 10), // amount0Max (10% slippage buffer)
            amount1 + (amount1 / 10), // amount1Max (10% slippage buffer)
            msg.sender, // recipient of the NFT position
            bytes("") // hookData
        );

        // SETTLE_PAIR params: (currency0, currency1)
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        // Encode for modifyLiquidities
        bytes memory unlockData = abi.encode(actions, params);

        // Set deadline to 1 hour from now
        uint256 deadline = block.timestamp + 3600;

        // Execute the liquidity addition
        positionManager.modifyLiquidities(unlockData, deadline);

        console2.log("Liquidity added successfully!");

        // ================================================================
        // DEPLOYMENT SUMMARY
        // ================================================================
        console2.log("\n========================================");
        console2.log("         DEPLOYMENT SUMMARY");
        console2.log("========================================");
        console2.log("Network: Base Sepolia");
        console2.log("");
        console2.log("Tokens:");
        console2.log("  cbBTC:", address(cbBTC));
        console2.log("  USDC:", address(usdc));
        console2.log("");
        console2.log("Pool:");
        console2.log("  PoolManager:", POOL_MANAGER);
        console2.log("  PositionManager:", POSITION_MANAGER);
        console2.log("  Currency0:", token0);
        console2.log("  Currency1:", token1);
        console2.log("  Fee:", SWAP_FEE);
        console2.log("  Tick Spacing:", TICK_SPACING);
        console2.log("");
        console2.log("Liquidity Position:");
        console2.log("  Tick Lower:", TICK_LOWER);
        console2.log("  Tick Upper:", TICK_UPPER);
        console2.log("  Liquidity:", liquidity);
        console2.log("========================================");

        vm.stopBroadcast();
    }
}
