// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BinaryConditionalTokens} from "./BinaryConditionalTokens.sol";
import {ProposalFactory} from "./ProposalFactory.sol";

/// @title Resolver
/// @notice Oracle for BinaryConditionalTokens. On resolve(), reads the KPI value
///         from `kpiTarget` (native balance or ERC-20), normalizes to [0, DENOM],
///         and reports the winning branch's scalar numerators. The losing branch
///         resolves to (DENOM/2, DENOM/2) → void (every token redeems at 0.5).
contract Resolver {
    uint128 public constant DENOM = 10_000;

    BinaryConditionalTokens public immutable bct;
    ProposalFactory public immutable factory;

    event Resolved(uint256 indexed proposalId, uint256 kpiValue, uint128 winningNumYes);

    constructor(BinaryConditionalTokens _bct, ProposalFactory _factory) {
        bct = _bct;
        factory = _factory;
    }

    function resolve(uint256 proposalId) external {
        (address target, address token, uint256 observationBlock, uint256 lo, uint256 hi, ProposalFactory.State state) =
            factory.getKPIConfig(proposalId);
        require(block.number >= observationBlock, "Resolver: early");

        bool passWon = state == ProposalFactory.State.DecidedPass;
        bool failWon = state == ProposalFactory.State.DecidedFail;
        require(passWon || failWon, "Resolver: not decided");

        uint256 kpi = token == address(0) ? target.balance : IERC20(token).balanceOf(target);
        uint128 numYes = _normalize(kpi, lo, hi);
        uint128 numNo = DENOM - numYes;

        (bytes32 passQ, bytes32 failQ) = factory.getQuestionIds(proposalId);

        if (passWon) {
            bct.reportPayouts(passQ, numNo, numYes, DENOM);
            bct.reportPayouts(failQ, DENOM / 2, DENOM / 2, DENOM);
        } else {
            bct.reportPayouts(passQ, DENOM / 2, DENOM / 2, DENOM);
            bct.reportPayouts(failQ, numNo, numYes, DENOM);
        }

        factory.markResolved(proposalId);
        emit Resolved(proposalId, kpi, numYes);
    }

    /// @dev Clip KPI to [lo, hi] and scale to [0, DENOM].
    function _normalize(uint256 kpi, uint256 lo, uint256 hi) internal pure returns (uint128) {
        if (kpi <= lo) return 0;
        if (kpi >= hi) return DENOM;
        return uint128(((kpi - lo) * DENOM) / (hi - lo));
    }
}
