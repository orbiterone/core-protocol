// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.10;

abstract contract IncentiveInterface {
    function distributeSupplier(address cToken, address supplier)
        external
        virtual;

    function distributeBorrower(address cToken, address borrower)
        external
        virtual;

    mapping(address => mapping(address => uint)) public rewardAccrued;

    mapping(address => mapping(address => uint)) public supplyRewardSpeeds;

    mapping(address => mapping(address => uint)) public borrowRewardSpeeds;

    function getAllSupportIncentives()
        public
        view
        virtual
        returns (address[] memory);
}
