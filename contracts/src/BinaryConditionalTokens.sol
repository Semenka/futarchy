// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title BinaryConditionalTokens
/// @notice Minimal binary-outcome conditional token (ERC-1155). MVP stand-in for
///         Gnosis CTF while we're on Solidity 0.8. Interface intentionally mirrors
///         CTF (conditionId, indexSet semantics, scalar payoutNumerators) so the
///         swap to canonical CTF is mechanical. Binary only — no arbitrary
///         partitions, no nested conditions.
///
///         indexSet layout:
///           0b01 = NO outcome  (index 0)
///           0b10 = YES outcome (index 1)
///
///         Scalar resolution: oracle reports `(num0, num1, denom)` with
///         `num0 + num1 == denom`. Each outcome token redeems for
///         `balance * num[bit] / denom` of collateral. Binary "YES wins"
///         is `(0, denom, denom)`; "void" is `(denom/2, denom/2, denom)`.
contract BinaryConditionalTokens is ERC1155 {
    using SafeERC20 for IERC20;

    struct Condition {
        address oracle;
        bytes32 questionId;
        bool resolved;
        uint128 numerator0; // payout weight for indexSet 0b01 (NO / SHORT)
        uint128 numerator1; // payout weight for indexSet 0b10 (YES / LONG)
        uint128 denominator;
    }

    mapping(bytes32 => Condition) public conditions;

    event ConditionPreparation(bytes32 indexed conditionId, address indexed oracle, bytes32 indexed questionId);
    event ConditionResolution(bytes32 indexed conditionId, uint128 numerator0, uint128 numerator1, uint128 denominator);
    event PositionSplit(address indexed stakeholder, bytes32 indexed conditionId, IERC20 collateral, uint256 amount);
    event PositionsMerge(address indexed stakeholder, bytes32 indexed conditionId, IERC20 collateral, uint256 amount);
    event PayoutRedemption(address indexed redeemer, bytes32 indexed conditionId, IERC20 collateral, uint256 payout);

    constructor() ERC1155("") {}

    /// @dev Mirrors CTF: conditionId = keccak(oracle, questionId, outcomeSlotCount).
    ///      outcomeSlotCount fixed to 2 here.
    function getConditionId(address oracle, bytes32 questionId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(oracle, questionId, uint256(2)));
    }

    /// @dev indexSet layout (binary, but Solidity has no binary literals):
    ///        INDEX_NO  = 1 (0b01) → NO  / SHORT outcome
    ///        INDEX_YES = 2 (0b10) → YES / LONG  outcome
    uint256 public constant INDEX_NO = 1;
    uint256 public constant INDEX_YES = 2;

    /// @dev Simplified positionId: keccak(conditionId, indexSet). Real CTF threads
    ///      parentCollectionId + collateral — we skip since no nesting, one collateral per market.
    function getPositionId(bytes32 conditionId, uint256 indexSet) public pure returns (uint256) {
        require(indexSet == INDEX_NO || indexSet == INDEX_YES, "BCT: bad indexSet");
        return uint256(keccak256(abi.encodePacked(conditionId, indexSet)));
    }

    function prepareCondition(address oracle, bytes32 questionId) external returns (bytes32 conditionId) {
        conditionId = getConditionId(oracle, questionId);
        require(conditions[conditionId].oracle == address(0), "BCT: exists");
        conditions[conditionId] = Condition({
            oracle: oracle,
            questionId: questionId,
            resolved: false,
            numerator0: 0,
            numerator1: 0,
            denominator: 0
        });
        emit ConditionPreparation(conditionId, oracle, questionId);
    }

    /// @notice Deposit `amount` collateral, receive `amount` of each outcome token.
    function splitPosition(IERC20 collateral, bytes32 conditionId, uint256 amount) external {
        require(conditions[conditionId].oracle != address(0), "BCT: unknown condition");
        require(!conditions[conditionId].resolved, "BCT: resolved");

        collateral.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, getPositionId(conditionId, INDEX_NO), amount, "");
        _mint(msg.sender, getPositionId(conditionId, INDEX_YES), amount, "");

        emit PositionSplit(msg.sender, conditionId, collateral, amount);
    }

    /// @notice Burn equal amounts of both outcome tokens to reclaim collateral.
    function mergePositions(IERC20 collateral, bytes32 conditionId, uint256 amount) external {
        require(!conditions[conditionId].resolved, "BCT: resolved");

        _burn(msg.sender, getPositionId(conditionId, INDEX_NO), amount);
        _burn(msg.sender, getPositionId(conditionId, INDEX_YES), amount);
        collateral.safeTransfer(msg.sender, amount);

        emit PositionsMerge(msg.sender, conditionId, collateral, amount);
    }

    /// @notice Oracle reports scalar payout numerators. Must satisfy
    ///         `num0 + num1 == denom` and `denom > 0`.
    function reportPayouts(bytes32 questionId, uint128 num0, uint128 num1, uint128 denom) external {
        require(denom > 0, "BCT: zero denom");
        require(uint256(num0) + uint256(num1) == uint256(denom), "BCT: numerators");

        bytes32 conditionId = getConditionId(msg.sender, questionId);
        Condition storage c = conditions[conditionId];
        require(c.oracle == msg.sender, "BCT: not oracle");
        require(!c.resolved, "BCT: already resolved");

        c.resolved = true;
        c.numerator0 = num0;
        c.numerator1 = num1;
        c.denominator = denom;

        emit ConditionResolution(conditionId, num0, num1, denom);
    }

    /// @notice After resolution, burn outcome tokens and receive
    ///         `balance * numerator[bit] / denominator` collateral.
    function redeemPositions(IERC20 collateral, bytes32 conditionId, uint256[] calldata indexSets) external {
        Condition memory c = conditions[conditionId];
        require(c.resolved, "BCT: not resolved");

        uint256 totalPayout;
        for (uint256 i = 0; i < indexSets.length; i++) {
            uint256 indexSet = indexSets[i];
            uint256 positionId = getPositionId(conditionId, indexSet);
            uint256 bal = balanceOf(msg.sender, positionId);
            if (bal == 0) continue;

            _burn(msg.sender, positionId, bal);

            uint128 num = indexSet == INDEX_YES ? c.numerator1 : c.numerator0;
            totalPayout += (bal * uint256(num)) / uint256(c.denominator);
        }
        if (totalPayout > 0) {
            collateral.safeTransfer(msg.sender, totalPayout);
        }
        emit PayoutRedemption(msg.sender, conditionId, collateral, totalPayout);
    }
}
