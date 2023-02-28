// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";

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

contract RandomNumberGenerator is Ownable {
    address public orbiterLottery;
    uint32 public randomResult;
    uint256 public latestLotteryId;

    uint256 private _randNonce = 0;

    constructor() {}

    function setLotteryAddress(address _orbiterLottery) external onlyOwner {
        orbiterLottery = _orbiterLottery;
    }

    function getRandomNumber(bytes32 _seed) external {
        require(msg.sender == orbiterLottery, "Only OrbiterLottery");

        uint256 rand = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, msg.sender, _seed, _randNonce)
            )
        );

        fulfillRandomWords(_randNonce, rand);
        _randNonce++;
    }

    function viewLatestLotteryId() external view returns (uint256) {
        return latestLotteryId;
    }

    function viewRandomResult() external view returns (uint32) {
        return randomResult;
    }

    function fulfillRandomWords(uint256 nonce, uint256 randomWords) internal {
        require(nonce == _randNonce, "Wrong nonce");
        randomResult = uint32(1000000 + (randomWords % 1000000));
        latestLotteryId = OrbitLottery(orbiterLottery).viewCurrentLotteryId();
    }
}
