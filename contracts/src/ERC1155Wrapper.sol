// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title ERC1155Wrapper
/// @notice 1:1 wraps a single (ERC-1155 contract, id) pair into an ERC-20. One
///         wrapper per outcome positionId, deployed by ProposalFactory. Lets the
///         V2-fork AMM treat outcome tokens as fungible ERC-20s.
contract ERC1155Wrapper is ERC20, IERC1155Receiver {
    IERC1155 public immutable underlying;
    uint256 public immutable tokenId;

    constructor(IERC1155 _underlying, uint256 _tokenId, string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {
        underlying = _underlying;
        tokenId = _tokenId;
    }

    /// @notice Deposit `amount` of underlying ERC-1155 token; mints ERC-20 1:1.
    function wrap(uint256 amount) external {
        underlying.safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        _mint(msg.sender, amount);
    }

    /// @notice Burn `amount` ERC-20 and receive underlying ERC-1155 1:1.
    function unwrap(uint256 amount) external {
        _burn(msg.sender, amount);
        underlying.safeTransferFrom(address(this), msg.sender, tokenId, amount, "");
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
