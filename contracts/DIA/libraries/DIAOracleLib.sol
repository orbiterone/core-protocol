// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.10;

interface IDIAOracleV2 {
    function getValue(string memory) external view returns (uint128, uint128);
}

interface WSTKsmAdapter {
    function wstKSMPrice() external view returns (uint256);
}

interface D2OAdapter {
    function getPrice(string memory key) external view returns (uint256);
}
