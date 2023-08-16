// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./PriceOracle.sol";
import "./IncentiveInterface.sol";
import "./CTokenInterfaces.sol";
import "./EIP20Interface.sol";
import "./ExponentialNoError.sol";
import "./Lottery/interfaces/IOrbitLottery.sol";

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

    IncentiveInterface public incentive;

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

    IOrbitLottery lottery;

    struct IncentiveInfo {
        string tokenName;
        string tokenSymbol;
        uint8 tokenDecimal;
        address token;
        uint256 reward;
    }

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

    struct TicketsInfo {
        uint256 ticketId;
        uint32 ticketNumber;
        bool claimStatus;
        bool winning;
        bool[] matches;
    }

    struct LotteryInfoByAccount {
        uint256 totalTickets;
        uint256 winningTickets;
        TicketsInfo[] tickets;
    }

    constructor(address _comptroller, address _lottery) {
        comptroller = IComp(_comptroller);
        lottery = IOrbitLottery(_lottery);
    }

    function setComptroller(address _comptroller) external onlyOwner {
        require(
            IComp(_comptroller).isComptroller() == true,
            "ReaderOrbiter::setComptroller: contract is not comptroller"
        );

        comptroller = IComp(_comptroller);
    }

    function setLottery(address _lottery) external onlyOwner {
        require(
            IOrbitLottery(_lottery).viewCurrentLotteryId() > 0,
            "ReaderOrbiter::setLottery: contract is not lottery"
        );

        lottery = IOrbitLottery(_lottery);
    }

    function incentives(
        address _account
    ) external returns (IncentiveInfo[] memory) {
        IncentiveInterface incentive = comptroller.incentive();
        CToken[] memory supportMarkets = comptroller.getAllMarkets();

        address[] memory supportIncentives = incentive
            .getAllSupportIncentives();

        IncentiveInfo[] memory incentivesData = new IncentiveInfo[](
            supportIncentives.length
        );

        for (uint256 i = 0; i < supportIncentives.length; i++) {
            EIP20Interface itemIncentive = EIP20Interface(supportIncentives[i]);
            for (uint256 j = 0; j < supportMarkets.length; j++) {
                CTokenInterface asset = supportMarkets[j];

                if (
                    incentive.supplyRewardSpeeds(
                        address(itemIncentive),
                        address(asset)
                    ) > 0
                ) {
                    incentive.distributeSupplier(address(asset), _account);
                }

                if (
                    incentive.borrowRewardSpeeds(
                        address(itemIncentive),
                        address(asset)
                    ) > 0
                ) {
                    incentive.distributeBorrower(address(asset), _account);
                }
            }

            uint256 reward = incentive.rewardAccrued(
                address(itemIncentive),
                _account
            );

            incentivesData[i] = IncentiveInfo({
                tokenName: itemIncentive.name(),
                tokenSymbol: itemIncentive.symbol(),
                tokenDecimal: itemIncentive.decimals(),
                token: address(itemIncentive),
                reward: reward
            });
        }

        return incentivesData;
    }

    function marketInfoByAccount(
        address _account
    )
        external
        returns (
            MarketUserInfo memory,
            MarketSupplyInfo[] memory,
            MarketBorrowInfo[] memory
        )
    {
        CToken[] memory supportMarkets = comptroller.getAllMarkets();
        PriceOracle oracle = comptroller.oracle();

        AccountLiquidityLocalVars memory vars; // Holds all our calculation results

        MarketUserInfo memory marketInfo;
        MarketSupplyInfo[] memory supplied = new MarketSupplyInfo[](
            supportMarkets.length
        );
        MarketBorrowInfo[] memory borrowed = new MarketBorrowInfo[](
            supportMarkets.length
        );

        for (uint256 i = 0; i < supportMarkets.length; i++) {
            CTokenInterface asset = supportMarkets[i];
            asset.accrueInterest();
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
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(
                CToken(address(asset))
            );
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            bool checkAsset = comptroller.checkMembership(
                _account,
                CToken(address(asset))
            );
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

        if (marketInfo.totalCollateral > 0) {
            marketInfo.availableToWithdraw = mul_ScalarTruncate(
                Exp({mantissa: marketInfo.availableToBorrow}),
                div_(
                    Exp({mantissa: marketInfo.totalSupply}),
                    Exp({mantissa: marketInfo.totalCollateral})
                ).mantissa
            );
        }

        return (marketInfo, supplied, borrowed);
    }

    function ticketsUserByLottery(
        address _account,
        uint256 _lotteryId,
        uint256 _cursor,
        uint256 _size
    ) external view returns (LotteryInfoByAccount memory) {
        LotteryInfoByAccount memory vars;

        (
            uint256[] memory ticketIds,
            uint32[] memory ticketNumbers,
            bool[] memory ticketStatuses,

        ) = lottery.viewUserInfoForLotteryId(
                _account,
                _lotteryId,
                _cursor,
                _size
            );

        if (ticketIds.length > 0) {
            vars.totalTickets = ticketIds.length;
            vars.tickets = new TicketsInfo[](ticketIds.length);

            for (uint256 i = 0; i < ticketIds.length; i++) {
                uint256 ticketId = ticketIds[i];

                vars.tickets[i] = TicketsInfo({
                    ticketId: ticketId,
                    ticketNumber: ticketNumbers[i],
                    claimStatus: ticketStatuses[i],
                    winning: false,
                    matches: new bool[](6)
                });

                for (uint32 bracket = 0; bracket <= 5; bracket++) {
                    uint256 checkReward = lottery.viewRewardsForTicketId(
                        _lotteryId,
                        ticketId,
                        bracket
                    );
                    vars.tickets[i].matches[bracket] = checkReward > 0
                        ? true
                        : false;

                    if (checkReward > 0) {
                        vars.tickets[i].winning = true;
                    }
                }
                if (vars.tickets[i].winning) {
                    vars.winningTickets++;
                }
            }
        }

        return vars;
    }
}
