// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.10;

abstract contract IncentiveInterface {
    function distributeSupplier(address cToken, address supplier)
        external
        virtual;

    function distributeBorrower(address cToken, address borrower)
        external
        virtual;
}
