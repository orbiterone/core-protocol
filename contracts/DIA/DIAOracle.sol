// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../PriceOracle.sol";
import "../CErc20.sol";
import "../EIP20Interface.sol";
import "../SafeMath.sol";
import "../EIP20Interface.sol";
import "./libraries/DIAOracleLib.sol";

contract DIAOracle is Ownable, PriceOracle {
    using SafeMath for uint256;
    IDIAOracleV2 ORACLE;
    WSTKsmAdapter KSM_ADAPTER;

    event KeySet(address oToken, string key);

    mapping(address => string) internal _assets;

    constructor(address _oracle, address _ksmAdapter) {
        ORACLE = IDIAOracleV2(_oracle);
        KSM_ADAPTER = WSTKsmAdapter(_ksmAdapter);
    }

    function setOracle(address _oracle) external onlyOwner {
        (uint128 price, ) = IDIAOracleV2(_oracle).getValue("ETH/USD");
        require(price > 0, "DIAOracle::setOracle: contract is not oracle");

        ORACLE = IDIAOracleV2(_oracle);
    }

    function setWstKsmAdapter(address _ksmAdapter) external onlyOwner {
        uint256 price = WSTKsmAdapter(_ksmAdapter).wstKSMPrice();
        require(
            price > 0,
            "DIAOracle::setWstKsmAdapter: contract is not ksm adapter"
        );

        KSM_ADAPTER = WSTKsmAdapter(_ksmAdapter);
    }

    function setAsset(string calldata key, CToken cToken) external onlyOwner {
        require(
            address(cToken) != address(0) && compareStrings(key, "") == false,
            "DIAOracle::setAsset: invalid key"
        );
        emit KeySet(address(cToken), key);
        _assets[address(cToken)] = key;
    }

    function getUnderlyingPrice(CToken oToken)
        public
        view
        override
        returns (uint256)
    {
        string memory key = _assets[address(oToken)];
        string memory symbol = oToken.symbol();
        uint256 decimal = 18;
        uint256 priceLast = 0;
        if (compareStrings(symbol, "oMOVR") == false) {
            EIP20Interface token = EIP20Interface(
                CErc20(address(oToken)).underlying()
            );
            decimal = token.decimals();
        }

        if (compareStrings(symbol, "owstKSM")) {
            priceLast = KSM_ADAPTER.wstKSMPrice();
        } else {
            (uint128 price, ) = ORACLE.getValue(key);
            priceLast = uint256(price);
        }

        priceLast = uint256(priceLast).mul(10**(36 - 8 - decimal));

        return priceLast;
    }

    function compareStrings(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return (keccak256(abi.encodePacked((a))) ==
            keccak256(abi.encodePacked((b))));
    }
}
