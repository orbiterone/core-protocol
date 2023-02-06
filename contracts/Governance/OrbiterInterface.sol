// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.10;

abstract contract OrbiterInterface {
    function allowance(address account, address spender)
        external
        view
        virtual
        returns (uint256);

    function approve(address spender, uint256 rawAmount)
        external
        virtual
        returns (bool);

    function balanceOf(address account) external view virtual returns (uint256);

    function transfer(address dst, uint256 rawAmount)
        external
        virtual
        returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 rawAmount
    ) external virtual returns (bool);

    function delegate(address delegatee) public virtual;

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual;

    function getCurrentVotes(address account)
        external
        view
        virtual
        returns (uint96);

    function getPriorVotes(address account, uint256 blockNumber)
        public
        view
        virtual
        returns (uint96);
}
