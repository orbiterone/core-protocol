// SPDX-License-Identifier: MIT

import "./RandomnessConsumer.sol";

pragma solidity 0.8.10;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this;
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "New owner can not be the ZERO address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IRandomNumberGenerator {
    /**
     * Requests randomness from a user-provided seed
     */
    function getRandomNumber(bytes32 _seed) external;

    /**
     * View latest lotteryId numbers
     */
    function viewLatestLotteryId() external view returns (uint256);

    /**
     * Views random result
     */
    function viewRandomResult() external view returns (uint32);
}

interface OrbitLottery {
    function buyTickets(uint256 _lotteryId, uint32[] calldata _ticketNumbers)
        external
        payable;

    function claimTickets(
        uint256 _lotteryId,
        uint256[] calldata _ticketIds,
        uint32[] calldata _brackets
    ) external;

    function closeLottery(uint256 _lotteryId) external;

    function drawFinalNumberAndMakeLotteryClaimable(
        uint256 _lotteryId,
        bool _autoInjection
    ) external;

    function injectFunds(uint256 _lotteryId, uint256 _amount) external payable;

    function startLottery(
        uint256 _endTime,
        uint256 _priceTicket,
        uint256 _discountDivisor,
        uint256[6] calldata _rewardsBreakdown,
        uint256 _treasuryFee
    ) external;

    function viewCurrentLotteryId() external returns (uint256);
}

// File: contracts/RandomNumberGenerator.sol

pragma solidity ^0.8.4;

contract RandomNumberGenerator is
    RandomnessConsumer,
    IRandomNumberGenerator,
    Ownable
{
    address public orbiterLottery;
    uint256 public latestRequestId;
    uint32 public randomResult;
    uint256 public fee;
    uint256 public latestLotteryId;

    constructor() payable RandomnessConsumer() {}

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function setLotteryAddress(address _orbiterLottery) external onlyOwner {
        orbiterLottery = _orbiterLottery;
    }

    function getRandomNumber(bytes32 _seed) external override {
        require(msg.sender == orbiterLottery, "Only OrbiterLottery");

        latestRequestId = requestRandomness(fee, _seed);
    }

    function viewLatestLotteryId() external view override returns (uint256) {
        return latestLotteryId;
    }

    function viewRandomResult() external view override returns (uint32) {
        return randomResult;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords)
        internal
        override
    {
        require(latestRequestId == requestId, "Wrong requestId");
        randomResult = uint32(1000000 + (randomWords[0] % 1000000));
        latestLotteryId = OrbitLottery(orbiterLottery).viewCurrentLotteryId();
    }

    function increaseRequestFee() external payable {
        randomness.increaseRequestFee(latestRequestId, msg.value);
    }
}
