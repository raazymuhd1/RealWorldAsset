// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OracleLib, AggregatorV3Interface} from "./libraries/OracleLib.sol";

/*
 * @dev the codebase will mint sTSLA based on the collateral 
 * deposited into this contract. In our example, ETH is the
 * collateral that we will use to mint sTSLA.
 * 
   @dev this type of token is indirectly backed (synthetic (buatan)) 
 * This codebase is NOT COMPLETE
 * 
 * As far as the incentives to do this, people who want to 
 * short tesla and long eth would have the incentive to do this. 
 */
contract sTSLA is ERC20 {
    using OracleLib for AggregatorV3Interface;

    error sTSLA_feeds__InsufficientCollateral();

    // These both have 8 decimal places for Polygon
    // https://docs.chain.link/data-feeds/price-feeds/addresses?network=polygon
    address private i_tslaFeed;
    address private i_ethUsdFeed;
    uint256 public constant DECIMALS = 8;
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 public constant PRECISION = 1e18; // precision is 1
    // ambang batas collateral harus di atas 50%, di bawah 50% bisa di liquidate (di cairkan)
    // in lending protocol someone could liquidate somebody else collateral if that person collaterals is below 50%, and depositing another collateral equal to 200% from their borrow token (borrow $100 token => deposit $200 worth of collateral asset (ETH, USDT, etc))
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized from the minted amount or borrowed amount in lending protocol (mint $100 token = collateral token must be $2000 (200% from $100 worth of minted token))
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100; // liquidation precision is 100%
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // min health factor is 1.

    mapping(address user => uint256 tslaMinted) public s_tslaMintedPerUser;
    mapping(address user => uint256 ethCollateral) public s_ethCollateralPerUser;

    constructor(address tslaFeed, address ethUsdFeed) ERC20("Synthetic Tesla (Feeds)", "sTSLA") {
        i_tslaFeed = tslaFeed;
        i_ethUsdFeed = ethUsdFeed;
    }

    /* 
     * @dev User must deposit at least 200% of the value of the sTSLA they want to mint ( mint $100 worth of collateral, user must deposit $2000 worth of collateral to this contract )
     @dev challenge - implement a real world asset price using any oracle
     */
    function depositAndmint(uint256 amountToMint) external payable {
        // Checks / Effects
        s_ethCollateralPerUser[msg.sender] += msg.value;
        s_tslaMintedPerUser[msg.sender] += amountToMint;
        uint256 healthFactor = getHealthFactor(msg.sender);
        // transaction will revert if health factor below 1
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert sTSLA_feeds__InsufficientCollateral();
        }
        _mint(msg.sender, amountToMint);
        // No external interactions
    }

    /**
      @dev this function meant to redeem the collateral assets (ETH) and burn the sTSLA token (tokenized TSLA shares)
      @param amountToRedeem - amount of TSLA tokenized (shares) they want to sell, and get collateral token in return (ETH)
     */
    function redeemAndBurn(uint256 amountToRedeem) external {
        // Checks / Effects
        uint256 valueRedeemed = getUsdAmountFromTsla(amountToRedeem);
        uint256 ethToReturn = getEthAmountFromUsd(valueRedeemed);
        s_tslaMintedPerUser[msg.sender] -= amountToRedeem;
        uint256 healthFactor = getHealthFactor(msg.sender);
        // if health factor is 1 or above then its cool, otherwise it could be liquidated as its not healthy anymore
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert sTSLA_feeds__InsufficientCollateral();
        }
        _burn(msg.sender, amountToRedeem);
        // External
        (bool success,) = msg.sender.call{value: ethToReturn}("");
        if (!success) {
            revert("sTSLA_feeds: transfer failed");
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW AND PURE
    //////////////////////////////////////////////////////////////*/
    function getHealthFactor(address user) public view returns (uint256) {
        (uint256 totalTslaMintedValueInUsd, uint256 totalCollateralEthValueInUsd) = getAccountInformationValue(user);
        // this will return number of health factor based on user collateral divided by minted token value in USD
        return _calculateHealthFactor(totalTslaMintedValueInUsd, totalCollateralEthValueInUsd);
    }

    function getUsdAmountFromTsla(uint256 amountTslaInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_tslaFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // (1000 sTSLA * (priceInUsd * 1_000_000_000_0)) / 1_000_000_000_000_000_000
        return (amountTslaInWei * (uint256(price) * ADDITIONAL_FEED_PRECISION)) / PRECISION;
    }

    function getUsdAmountFromEth(uint256 ethAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_ethUsdFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (ethAmountInWei * (uint256(price) * ADDITIONAL_FEED_PRECISION)) / PRECISION;
    }

    function getEthAmountFromUsd(uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(i_ethUsdFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / ((uint256(price) * ADDITIONAL_FEED_PRECISION) * PRECISION);
    }

    function getAccountInformationValue(address user)
        public
        view
        returns (uint256 totalTslaMintedValueUsd, uint256 totalCollateralValueUsd)
    {
        (uint256 totalTslaMinted, uint256 totalCollateralEth) = _getAccountInformation(user);
        totalTslaMintedValueUsd = getUsdAmountFromTsla(totalTslaMinted);
        totalCollateralValueUsd = getUsdAmountFromEth(totalCollateralEth);
    }

    /**
        @param tslaMintedValueUsd - the number of tsla minted value in USD
        @param collateralValueUsd - the number of collateral value in USD
     */
    function _calculateHealthFactor(uint256 tslaMintedValueUsd, uint256 collateralValueUsd)
        internal
        pure
        returns (uint256)
    {
        if (tslaMintedValueUsd == 0) return type(uint256).max;
        // ($1000 (collateral token) * 50) / 100
        uint256 collateralAdjustedForThreshold = (collateralValueUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // collateral valueInUSD divided by tsla token minted valueInUSD 
        return (collateralAdjustedForThreshold * PRECISION) / tslaMintedValueUsd;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalTslaMinted, uint256 totalCollateralEth)
    {
        totalTslaMinted = s_tslaMintedPerUser[user];
        totalCollateralEth = s_ethCollateralPerUser[user];
    }
}
