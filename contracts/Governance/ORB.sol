// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./utils/address.sol";

contract ORBToken is ERC20, Ownable {
    using Address for address;

    constructor(uint256 initialSupply) ERC20("ORB token", "ORB") {
        _mint(msg.sender, initialSupply);
    }

    function multisend(address[] memory to, uint256[] memory values)
        external
        onlyOwner
    {
        require(
            to.length == values.length,
            "ORBToken::multisend: values and to must be equal length"
        );
        require(
            to.length < 200,
            "ORBToken::multisend: Values length must be max 200"
        );

        for (uint256 i; i < to.length; i++) {
            transfer(to[i], values[i]);
        }
    }

    function burnTokens(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }
}
