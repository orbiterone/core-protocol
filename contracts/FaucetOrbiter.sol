// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./EIP20Interface.sol";

contract FaucetOrbiter is Ownable {
    event Mint(address minter, uint256 mintAmount);

    uint256 private constant delayMint = 1 days;

    struct HistoryMint {
        address minter;
        uint256 amount;
        uint256 date;
    }

    mapping(address => uint256) private marketLimit;

    mapping(address => mapping(address => uint256)) private lastMint;

    mapping(address => HistoryMint[]) private historyMint;

    constructor(address[] memory markets, uint256[] memory limits) {
        require(
            markets.length == limits.length,
            "FaucetOrbiter::constructor: Markets and limits must be the same length."
        );

        for (uint256 i = 0; i < markets.length; i++) {
            address m = markets[i];
            uint256 l = limits[i];
            require(l > 0, "FaucetOrbiter::constructor: Limit must be more 0");
            marketLimit[m] = l;
        }
    }

    function setMarketLimit(address token, uint256 limit) external onlyOwner {
        require(
            limit > 0,
            "FaucetOrbiter::setMarketLimit: Limit must be more than 0"
        );

        marketLimit[token] = limit;
    }

    function getMarketLimit(address token) external view returns (uint256) {
        return marketLimit[token];
    }

    function balanceOf(address token) external view returns (uint256) {
        return EIP20Interface(token).balanceOf(address(this));
    }

    function getMintHistory(address token)
        external
        view
        returns (HistoryMint[] memory)
    {
        return historyMint[token];
    }

    function mint(address token) external {
        address sender = msg.sender;
        uint256 limit = marketLimit[token];
        uint256 timestamp = block.timestamp;
        require(
            limit > 0,
            "FaucetOrbiter::mint: Mint this token is not allowed"
        );
        uint256 lm = lastMint[token][sender];
        require(
            lm == 0 || (lm > 0 && timestamp - lm >= delayMint),
            "FaucetOrbiter::mint: Mint is limited for this address"
        );
        uint256 balanceToken = EIP20Interface(token).balanceOf(address(this));
        require(
            balanceToken >= limit,
            "FaucetOrbiter::mint: Token balance is less than the mint limit"
        );
        lastMint[token][sender] = timestamp;
        historyMint[token].push(
            HistoryMint({minter: sender, amount: limit, date: timestamp})
        );
        EIP20Interface(token).transfer(sender, limit);

        emit Mint(sender, limit);
    }
}
