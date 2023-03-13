// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./EIP20Interface.sol";
import "./CTokenInterfaces.sol";
import "./ExponentialNoError.sol";
import "./CToken.sol";

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

    mapping(address => Market) public markets;

    function getAllMarkets() public view virtual returns (CToken[] memory);

    function getAccountLiquidity(
        address account
    ) public view virtual returns (uint256, uint256, uint256);

    function checkMembership(
        address account,
        CToken cToken
    ) external view virtual returns (bool);
}

contract Incentive is Ownable, ExponentialNoError {
    IComp public comptroller;

    struct RewardMarketState {
        uint224 index;
        uint32 block;
    }

    event DistributedSupplierReward(
        address indexed incentive,
        CToken indexed cToken,
        address indexed supplier,
        uint256 delta,
        uint256 supplyIndex
    );

    event DistributedBorrowerReward(
        address indexed incentive,
        CToken indexed cToken,
        address indexed borrower,
        uint256 delta,
        uint256 borrowIndex
    );

    event RewardGranted(address incentive, address recipient, uint256 amount);

    uint224 public constant rewardInitialIndex = 1e36;

    address[] public supportIncentive;

    mapping(address => mapping(address => uint)) public supplyRewardSpeeds;

    mapping(address => mapping(address => uint)) public borrowRewardSpeeds;

    mapping(address => mapping(address => RewardMarketState))
        public rewardSupplyState;

    mapping(address => mapping(address => RewardMarketState))
        public rewardBorrowState;

    mapping(address => mapping(address => mapping(address => uint)))
        public rewardSupplierIndex;

    mapping(address => mapping(address => mapping(address => uint)))
        public rewardBorrowerIndex;

    mapping(address => mapping(address => uint)) public rewardAccrued;

    modifier isComptroller(address _comptroller) {
        require(
            IComp(_comptroller).isComptroller() == true,
            "Incentive::constructor: contract is not comptroller"
        );

        _;
    }

    modifier isSupportIncentive(address _incentiveAsset) {
        bool findInventive = false;
        for (uint256 i = 0; i < supportIncentive.length; i++) {
            if (supportIncentive[i] == _incentiveAsset) {
                findInventive = true;
                break;
            }
        }
        require(findInventive, "Incentive asset is not supported");

        _;
    }

    modifier isNotSupportIncentive(address _incentiveAsset) {
        bool findInventive = false;
        for (uint256 i = 0; i < supportIncentive.length; i++) {
            if (supportIncentive[i] == _incentiveAsset) {
                findInventive = true;
                break;
            }
        }
        require(!findInventive, "Incentive asset already support");

        _;
    }

    constructor(address _comptroller) isComptroller(_comptroller) {
        comptroller = IComp(_comptroller);
    }

    function getBlockNumber() public view virtual returns (uint256) {
        return block.number;
    }

    function getAllSupportIncentives() public view returns (address[] memory) {
        return supportIncentive;
    }

    function setComptroller(
        address _comptroller
    ) external onlyOwner isComptroller(_comptroller) {
        comptroller = IComp(_comptroller);
    }

    function supportIncentiveAsset(
        address _asset
    ) external onlyOwner isNotSupportIncentive(_asset) {
        EIP20Interface(_asset).totalSupply();

        supportIncentive.push(_asset);
    }

    function deleteIncentive(uint _index) external onlyOwner {
        supportIncentive[_index] = supportIncentive[
            supportIncentive.length - 1
        ];
        supportIncentive.pop();
    }

    function setRewardSpeed(
        address _incentiveAsset,
        CToken _cToken,
        uint256 _supplyRewardSpeed,
        uint256 _borrowRewardSpeed
    ) public isSupportIncentive(_incentiveAsset) onlyOwner {
        setRewardSpeedInternal(
            _incentiveAsset,
            _cToken,
            _supplyRewardSpeed,
            _borrowRewardSpeed
        );
    }

    function setRewardSpeedInternal(
        address incentiveAsset,
        CToken cToken,
        uint256 supplySpeed,
        uint256 borrowSpeed
    ) internal {
        (bool isListed, , ) = comptroller.markets(address(cToken));
        require(isListed, "market is not listed");

        if (
            supplyRewardSpeeds[incentiveAsset][address(cToken)] != supplySpeed
        ) {
            updateRewardSupplyIndex(incentiveAsset, address(cToken));
            supplyRewardSpeeds[incentiveAsset][address(cToken)] = supplySpeed;
        }

        if (
            borrowRewardSpeeds[incentiveAsset][address(cToken)] != borrowSpeed
        ) {
            Exp memory borrowIndex = Exp({mantissa: cToken.borrowIndex()});
            updateRewardBorrowIndex(
                incentiveAsset,
                address(cToken),
                borrowIndex
            );

            borrowRewardSpeeds[incentiveAsset][address(cToken)] = borrowSpeed;
        }
    }

    function updateRewardSupplyIndex(
        address incentiveAsset,
        address cToken
    ) internal {
        RewardMarketState storage supplyState = rewardSupplyState[
            incentiveAsset
        ][cToken];
        uint256 supplySpeed = supplyRewardSpeeds[incentiveAsset][cToken];
        uint32 blockNumber = safe32(
            getBlockNumber(),
            "block number exceeds 32 bits"
        );
        uint256 deltaBlocks = sub_(
            uint256(blockNumber),
            uint256(supplyState.block)
        );
        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint256 supplyTokens = CToken(cToken).totalSupply();
            uint256 assetAccrued = mul_(deltaBlocks, supplySpeed);
            Double memory ratio = supplyTokens > 0
                ? fraction(assetAccrued, supplyTokens)
                : Double({mantissa: 0});
            supplyState.index = safe224(
                add_(Double({mantissa: supplyState.index}), ratio).mantissa,
                "new index exceeds 224 bits"
            );
            supplyState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            supplyState.block = blockNumber;
        }
    }

    function updateRewardBorrowIndex(
        address incentiveAsset,
        address cToken,
        Exp memory marketBorrowIndex
    ) internal {
        RewardMarketState storage borrowState = rewardBorrowState[
            incentiveAsset
        ][cToken];
        uint256 borrowSpeed = borrowRewardSpeeds[incentiveAsset][cToken];
        uint32 blockNumber = safe32(
            getBlockNumber(),
            "block number exceeds 32 bits"
        );
        uint256 deltaBlocks = sub_(
            uint256(blockNumber),
            uint256(borrowState.block)
        );
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint256 borrowAmount = div_(
                CToken(cToken).totalBorrows(),
                marketBorrowIndex
            );
            uint256 assetAccrued = mul_(deltaBlocks, borrowSpeed);
            Double memory ratio = borrowAmount > 0
                ? fraction(assetAccrued, borrowAmount)
                : Double({mantissa: 0});
            borrowState.index = safe224(
                add_(Double({mantissa: borrowState.index}), ratio).mantissa,
                "new index exceeds 224 bits"
            );
            borrowState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            borrowState.block = blockNumber;
        }
    }

    function distributeSupplierReward(
        address incentive,
        address cToken,
        address supplier
    ) internal {
        RewardMarketState storage supplyState = rewardSupplyState[incentive][
            cToken
        ];
        uint256 supplyIndex = supplyState.index;
        uint256 supplierIndex = rewardSupplierIndex[incentive][cToken][
            supplier
        ];

        rewardSupplierIndex[incentive][cToken][supplier] = supplyIndex;

        if (supplierIndex == 0 && supplyIndex >= rewardInitialIndex) {
            supplierIndex = rewardInitialIndex;
        }

        Double memory deltaIndex = Double({
            mantissa: sub_(supplyIndex, supplierIndex)
        });

        uint256 supplierTokens = CToken(cToken).balanceOf(supplier);

        uint256 supplierDelta = mul_(supplierTokens, deltaIndex);

        uint256 supplierAccrued = add_(
            rewardAccrued[incentive][supplier],
            supplierDelta
        );
        rewardAccrued[incentive][supplier] = supplierAccrued;

        emit DistributedSupplierReward(
            incentive,
            CToken(cToken),
            supplier,
            supplierDelta,
            supplyIndex
        );
    }

    function distributeBorrowerReward(
        address incentive,
        address cToken,
        address borrower,
        Exp memory marketBorrowIndex
    ) internal {
        RewardMarketState storage borrowState = rewardBorrowState[incentive][
            cToken
        ];
        uint256 borrowIndex = borrowState.index;
        uint256 borrowerIndex = rewardBorrowerIndex[incentive][cToken][
            borrower
        ];

        rewardBorrowerIndex[incentive][cToken][borrower] = borrowIndex;

        if (borrowerIndex == 0 && borrowIndex >= rewardInitialIndex) {
            borrowerIndex = rewardInitialIndex;
        }

        Double memory deltaIndex = Double({
            mantissa: sub_(borrowIndex, borrowerIndex)
        });

        uint256 borrowerAmount = div_(
            CToken(cToken).borrowBalanceStored(borrower),
            marketBorrowIndex
        );

        uint256 borrowerDelta = mul_(borrowerAmount, deltaIndex);

        uint256 borrowerAccrued = add_(
            rewardAccrued[incentive][borrower],
            borrowerDelta
        );
        rewardAccrued[incentive][borrower] = borrowerAccrued;

        emit DistributedBorrowerReward(
            incentive,
            CToken(cToken),
            borrower,
            borrowerDelta,
            borrowIndex
        );
    }

    function distributeSupplier(address cToken, address supplier) external {
        for (uint256 i = 0; i < supportIncentive.length; i++) {
            updateRewardSupplyIndex(supportIncentive[i], cToken);
            distributeSupplierReward(supportIncentive[i], cToken, supplier);
        }
    }

    function distributeBorrower(address cToken, address borrower) external {
        Exp memory borrowIndex = Exp({mantissa: CToken(cToken).borrowIndex()});
        for (uint256 i = 0; i < supportIncentive.length; i++) {
            updateRewardBorrowIndex(supportIncentive[i], cToken, borrowIndex);
            distributeBorrowerReward(
                supportIncentive[i],
                cToken,
                borrower,
                borrowIndex
            );
        }
    }

    function claimIncentive(
        address incentive,
        address holder
    ) public isSupportIncentive(incentive) {
        return claimIncentive(incentive, holder, comptroller.getAllMarkets());
    }

    function claimIncentive(
        address incentive,
        address holder,
        CToken[] memory cTokens
    ) public isSupportIncentive(incentive) {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimIncentive(incentive, holders, cTokens, true, true);
    }

    function claimIncentive(
        address incentive,
        address[] memory holders,
        CToken[] memory cTokens,
        bool borrowers,
        bool suppliers
    ) public isSupportIncentive(incentive) {
        for (uint256 i = 0; i < cTokens.length; i++) {
            CToken cToken = cTokens[i];
            (bool isListed, , ) = comptroller.markets(address(cToken));
            require(isListed, "market must be listed");
            if (borrowers == true) {
                Exp memory borrowIndex = Exp({mantissa: cToken.borrowIndex()});
                updateRewardBorrowIndex(
                    incentive,
                    address(cToken),
                    borrowIndex
                );
                for (uint256 j = 0; j < holders.length; j++) {
                    distributeBorrowerReward(
                        incentive,
                        address(cToken),
                        holders[j],
                        borrowIndex
                    );
                }
            }
            if (suppliers == true) {
                updateRewardSupplyIndex(incentive, address(cToken));
                for (uint256 j = 0; j < holders.length; j++) {
                    distributeSupplierReward(
                        incentive,
                        address(cToken),
                        holders[j]
                    );
                }
            }
        }
        for (uint256 j = 0; j < holders.length; j++) {
            rewardAccrued[incentive][holders[j]] = grantRewardInternal(
                incentive,
                holders[j],
                rewardAccrued[incentive][holders[j]]
            );
        }
    }

    function grantRewardInternal(
        address incentive,
        address user,
        uint256 amount
    ) internal returns (uint256) {
        EIP20Interface asset = EIP20Interface(incentive);
        uint256 rewardRemaining = asset.balanceOf(address(this));
        if (amount > 0 && amount <= rewardRemaining) {
            asset.transfer(user, amount);
            return 0;
        }
        return amount;
    }

    function _grantReward(
        address incentive,
        address recipient,
        uint256 amount
    ) public onlyOwner {
        uint256 amountLeft = grantRewardInternal(incentive, recipient, amount);
        require(amountLeft == 0, "insufficient incentive for grant");
        emit RewardGranted(incentive, recipient, amount);
    }
}
