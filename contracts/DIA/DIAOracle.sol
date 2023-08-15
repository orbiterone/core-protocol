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
    D2OAdapter D2O_ADAPTER;

    event KeySet(address oToken, string key);
    error PriceTooOld();

    struct AssetInfo {
        string key;
        uint128 maxTime;
    }

    mapping(address => AssetInfo) internal _assets;

    constructor(address _oracle, address _ksmAdapter, address _d2oAdapter) {
        ORACLE = IDIAOracleV2(_oracle);
        KSM_ADAPTER = WSTKsmAdapter(_ksmAdapter);
        D2O_ADAPTER = D2OAdapter(_d2oAdapter);
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

    function setd2OAdapter(address _d2oAdapter) external onlyOwner {
        uint256 price = D2OAdapter(_d2oAdapter).getPrice("USDC");
        require(
            price > 0,
            "DIAOracle::setd2OAdapter: contract is not d20 adapter"
        );

        D2O_ADAPTER = D2OAdapter(_d2oAdapter);
    }

    function setAsset(
        string calldata key,
        uint128 maxTime,
        CToken cToken
    ) external onlyOwner {
        require(
            address(cToken) != address(0) && compareStrings(key, "") == false,
            "DIAOracle::setAsset: invalid key"
        );
        emit KeySet(address(cToken), key);
        _assets[address(cToken)] = AssetInfo({key: key, maxTime: maxTime});
    }

    function getUnderlyingPrice(
        CToken oToken
    ) public view override returns (uint256 priceLast) {
        AssetInfo memory info = _assets[address(oToken)];
        string memory symbol = oToken.symbol();
        uint256 decimal = 18;
        uint128 timestamp = 0;
        uint128 price = 0;
        if (
            compareStrings(symbol, "oMOVR") == false &&
            compareStrings(symbol, "oGLMR") == false
        ) {
            EIP20Interface token = EIP20Interface(
                CErc20(address(oToken)).underlying()
            );
            decimal = token.decimals();
        }

        if (compareStrings(symbol, "owstKSM")) {
            priceLast = KSM_ADAPTER.wstKSMPrice();
        } else if (compareStrings(symbol, "od2O")) {
            priceLast = D2O_ADAPTER.getPrice("USDC");
            (, timestamp) = D2O_ADAPTER.getValue("USDC");
        } else {
            (price, timestamp) = ORACLE.getValue(info.key);
            priceLast = uint256(price);
        }
        if (timestamp > 0) {
            bool inTime = ((block.timestamp - timestamp) < info.maxTime)
                ? true
                : false;

            if (!inTime) revert PriceTooOld();
        }

        priceLast = uint256(priceLast).mul(10 ** (36 - 8 - decimal));

        return priceLast;
    }

    function compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) ==
            keccak256(abi.encodePacked((b))));
    }
}
