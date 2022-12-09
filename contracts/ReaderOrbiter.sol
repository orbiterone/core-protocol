// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./PriceOracle.sol";
import "./CTokenInterfaces.sol";
import "./ExponentialNoError.sol";

abstract contract IComp {
    struct Market {
        // Whether or not this market is listed
        bool isListed;
        //  Multiplier representing the most one can borrow against their collateral in this market.
        //  For instance, 0.9 to allow borrowing 90% of collateral value.
        //  Must be between 0 and 1, and stored as a mantissa.
        uint256 collateralFactorMantissa;
        // Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
        // Whether or not this market receives COMP
        bool isComped;
    }

    bool public constant isComptroller = true;

    PriceOracle public oracle;

    mapping(address => Market) public markets;

    function getAllMarkets() public view virtual returns (CToken[] memory);

    function getAccountLiquidity(address account)
        public
        view
        virtual
        returns (
            uint256,
            uint256,
            uint256
        );

    function checkMembership(address account, CToken cToken)
        external
        view
        virtual
        returns (bool);
}

contract ReaderOrbiter is Ownable, ExponentialNoError {
    IComp comptroller;

    struct MarketSupplyInfo {
        address oToken;
        uint256 totalSupply;
        bool collateral;
    }

    struct MarketBorrowInfo {
        address oToken;
        uint256 totalBorrow;
    }

    struct MarketUserInfo {
        uint256 totalSupply;
        uint256 totalBorrow;
        uint256 totalCollateral;
        uint256 availableToBorrow;
        uint256 availableToWithdraw;
    }

    struct AccountLiquidityLocalVars {
        uint256 sumCollateral;
        uint256 sumTotalSupply;
        uint256 sumBorrowPlusEffects;
        uint256 cTokenBalance;
        uint256 borrowBalance;
        uint256 exchangeRateMantissa;
        uint256 oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    constructor(address _comptroller) {
        comptroller = IComp(_comptroller);
    }

    function setComptroller(address _comptroller) external onlyOwner {
        require(
            IComp(_comptroller).isComptroller() == true,
            "ReaderOrbiter::setComptroller: contract is not comptroller"
        );

        comptroller = IComp(_comptroller);
    }

    function marketInfoByAccount(address _account)
        public
        view
        returns (MarketUserInfo memory, MarketSupplyInfo[] memory, MarketBorrowInfo[] memory)
    {
        CToken[] memory supportMarkets = comptroller.getAllMarkets();
        PriceOracle oracle = comptroller.oracle();

        AccountLiquidityLocalVars memory vars; // Holds all our calculation results

        MarketUserInfo memory marketInfo;
        MarketSupplyInfo[] memory supplied = new MarketSupplyInfo[](supportMarkets.length);
        MarketBorrowInfo[] memory borrowed = new MarketBorrowInfo[](supportMarkets.length);

        for (uint256 i = 0; i < supportMarkets.length; i++) {
            CToken asset = supportMarkets[i];
            // Read the balances and exchange rate from the cToken
            (
                ,
                vars.cTokenBalance,
                vars.borrowBalance,
                vars.exchangeRateMantissa
            ) = asset.getAccountSnapshot(_account);

            (, uint256 collateralFactorMantissa, ) = comptroller.markets(
                address(asset)
            );

            vars.collateralFactor = Exp({mantissa: collateralFactorMantissa});
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(asset);
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            bool checkAsset = comptroller.checkMembership(_account, asset);
            supplied[i] = MarketSupplyInfo({
                totalSupply: mul_(vars.cTokenBalance, vars.exchangeRate),
                oToken: address(asset),
                collateral: checkAsset
            });

            borrowed[i] = MarketBorrowInfo({
                totalBorrow: vars.borrowBalance,
                oToken: address(asset)
            });

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            if (checkAsset == true) {
                vars.tokensToDenom = mul_(
                    mul_(vars.collateralFactor, vars.exchangeRate),
                    vars.oraclePrice
                );

                // sumCollateral += tokensToDenom * cTokenBalance
                vars.sumCollateral = mul_ScalarTruncateAddUInt(
                    vars.tokensToDenom,
                    vars.cTokenBalance,
                    vars.sumCollateral
                );
            }
            

            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
                vars.oraclePrice,
                vars.borrowBalance,
                vars.sumBorrowPlusEffects
            );

            vars.sumTotalSupply = mul_ScalarTruncateAddUInt(
                vars.oraclePrice,
                mul_(vars.cTokenBalance, vars.exchangeRate),
                vars.sumTotalSupply
            );
        }

        marketInfo.totalSupply = vars.sumTotalSupply;
        marketInfo.totalCollateral = vars.sumCollateral;
        marketInfo.totalBorrow = vars.sumBorrowPlusEffects;
        (, marketInfo.availableToBorrow, ) = comptroller.getAccountLiquidity(
            _account
        );
        marketInfo.availableToWithdraw = mul_ScalarTruncate(
            Exp({mantissa: marketInfo.availableToBorrow}),
            div_(
                Exp({mantissa: marketInfo.totalSupply}),
                Exp({mantissa: marketInfo.totalCollateral})
            ).mantissa
        );

        return (marketInfo, supplied, borrowed);
    }
}
