// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {BinaryConditionalTokens} from "./BinaryConditionalTokens.sol";
import {ERC1155Wrapper} from "./ERC1155Wrapper.sol";
import {FutarchyAMM} from "./FutarchyAMM.sol";

/// @title ProposalFactory
/// @notice Spawns a futarchy proposal: prepares two scalar conditions (pass /
///         fail) on the same KPI, deploys one FutarchyAMM per branch, and
///         seeds both with neutral-prior liquidity (spot price 0.5). At
///         trading-window close, decide() compares TWAP long prices and
///         queues a TimelockController batch if pass > fail.
contract ProposalFactory is ERC1155Holder {
    using SafeERC20 for IERC20;

    enum State {
        None,
        Trading,
        DecidedPass,
        DecidedFail,
        Resolved
    }

    struct TWAPSnapshot {
        uint256 cumulative;
        uint32 timestamp;
    }

    struct Proposal {
        bytes32 passQuestionId;
        bytes32 failQuestionId;
        bytes32 passConditionId;
        bytes32 failConditionId;
        FutarchyAMM passAMM;
        FutarchyAMM failAMM;
        ERC1155Wrapper passLongWrapper;
        ERC1155Wrapper failLongWrapper;
        address proposer;
        uint256 tradingDeadline;
        uint256 kpiObservationBlock;
        uint256 kpiLo;
        uint256 kpiHi;
        uint256 seedCollateral;
        address kpiTarget; // address whose balance is the KPI
        address kpiToken;  // address(0) = native ETH, else ERC-20
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        bytes32 timelockSalt;
        TWAPSnapshot passSnapshot;
        TWAPSnapshot failSnapshot;
        State state;
    }

    IERC20 public immutable collateral;
    BinaryConditionalTokens public immutable bct;
    TimelockController public immutable timelock;
    address public immutable resolver;
    uint256 public immutable timelockDelay;

    uint256 public nextProposalId;
    mapping(uint256 => Proposal) internal proposals_;

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        bytes32 passConditionId,
        bytes32 failConditionId,
        address passAMM,
        address failAMM,
        uint256 tradingDeadline,
        uint256 kpiObservationBlock
    );
    event ProposalDecided(uint256 indexed proposalId, State outcome, uint256 passPrice, uint256 failPrice);
    event ProposalResolved(uint256 indexed proposalId);

    constructor(
        IERC20 _collateral,
        BinaryConditionalTokens _bct,
        TimelockController _timelock,
        address _resolver,
        uint256 _timelockDelay
    ) {
        collateral = _collateral;
        bct = _bct;
        timelock = _timelock;
        resolver = _resolver;
        timelockDelay = _timelockDelay;
    }

    struct CreateParams {
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        uint256 tradingWindow;
        uint256 observationDelayBlocks;
        uint256 kpiLo;
        uint256 kpiHi;
        uint256 seedCollateral;
        address kpiTarget;
        address kpiToken;
    }

    function createProposal(CreateParams calldata params) external returns (uint256 proposalId) {
        require(
            params.targets.length == params.values.length && params.values.length == params.calldatas.length,
            "PF: tx arity"
        );
        require(params.kpiHi > params.kpiLo, "PF: kpi range");
        require(params.seedCollateral > 0, "PF: seed");

        proposalId = nextProposalId++;
        Proposal storage p = proposals_[proposalId];
        p.proposer = msg.sender;
        p.tradingDeadline = block.timestamp + params.tradingWindow;
        p.kpiObservationBlock = block.number + params.observationDelayBlocks;
        p.kpiLo = params.kpiLo;
        p.kpiHi = params.kpiHi;
        p.seedCollateral = params.seedCollateral;
        p.kpiTarget = params.kpiTarget;
        p.kpiToken = params.kpiToken;
        p.targets = params.targets;
        p.values = params.values;
        p.calldatas = params.calldatas;
        p.timelockSalt = keccak256(abi.encode(proposalId, msg.sender, block.timestamp));
        p.state = State.Trading;

        p.passQuestionId = keccak256(abi.encode(proposalId, "pass"));
        p.failQuestionId = keccak256(abi.encode(proposalId, "fail"));
        p.passConditionId = bct.prepareCondition(resolver, p.passQuestionId);
        p.failConditionId = bct.prepareCondition(resolver, p.failQuestionId);

        uint256 passLongId = bct.getPositionId(p.passConditionId, bct.INDEX_YES());
        uint256 failLongId = bct.getPositionId(p.failConditionId, bct.INDEX_YES());

        p.passLongWrapper = new ERC1155Wrapper(IERC1155(address(bct)), passLongId, "Futarchy Pass LONG", "fPASS-L");
        p.failLongWrapper = new ERC1155Wrapper(IERC1155(address(bct)), failLongId, "Futarchy Fail LONG", "fFAIL-L");

        p.passAMM = new FutarchyAMM(collateral, IERC20(address(p.passLongWrapper)), "Futarchy Pass LP", "fPASS-LP");
        p.failAMM = new FutarchyAMM(collateral, IERC20(address(p.failLongWrapper)), "Futarchy Fail LP", "fFAIL-LP");

        _seedBranch(p.passConditionId, p.passLongWrapper, p.passAMM, params.seedCollateral);
        _seedBranch(p.failConditionId, p.failLongWrapper, p.failAMM, params.seedCollateral);

        // Take cumulative-price snapshot at creation; decide() reads TWAP over the full window.
        (,, uint32 passTs) = p.passAMM.getReserves();
        (,, uint32 failTs) = p.failAMM.getReserves();
        p.passSnapshot = TWAPSnapshot(p.passAMM.priceLongCumulativeLast(), passTs);
        p.failSnapshot = TWAPSnapshot(p.failAMM.priceLongCumulativeLast(), failTs);

        emit ProposalCreated(
            proposalId,
            msg.sender,
            p.passConditionId,
            p.failConditionId,
            address(p.passAMM),
            address(p.failAMM),
            p.tradingDeadline,
            p.kpiObservationBlock
        );
    }

    /// @dev Pulls 3x seed per branch from proposer. Splits 2x into LONG+SHORT,
    ///      wraps LONG, seeds AMM with (1x collateral, 2x wrapped LONG) → neutral prior.
    ///      SHORT tokens + LP shares are forwarded to the proposer.
    function _seedBranch(bytes32 conditionId, ERC1155Wrapper wrapper, FutarchyAMM amm, uint256 seed) internal {
        collateral.safeTransferFrom(msg.sender, address(this), seed * 3);
        collateral.forceApprove(address(bct), seed * 2);
        bct.splitPosition(collateral, conditionId, seed * 2);

        uint256 longId = wrapper.tokenId();
        bct.setApprovalForAll(address(wrapper), true);
        wrapper.wrap(seed * 2);
        // Transfer SHORT (unwrapped) to proposer
        bct.safeTransferFrom(address(this), msg.sender, bct.getPositionId(conditionId, bct.INDEX_NO()), seed * 2, "");

        collateral.forceApprove(address(amm), seed);
        IERC20(address(wrapper)).forceApprove(address(amm), seed * 2);
        amm.addLiquidity(seed, seed * 2, msg.sender);
        // Silence unused local
        longId;
    }

    /// @notice Read pass / fail TWAPs over the full trading window. If pass > fail,
    ///         schedule the Timelock batch; otherwise cancel. One-way state transition.
    function decide(uint256 proposalId) external {
        Proposal storage p = proposals_[proposalId];
        require(p.state == State.Trading, "PF: state");
        require(block.timestamp >= p.tradingDeadline, "PF: early");

        uint256 passPrice = p.passAMM.consultTWAP(p.passSnapshot.cumulative, p.passSnapshot.timestamp);
        uint256 failPrice = p.failAMM.consultTWAP(p.failSnapshot.cumulative, p.failSnapshot.timestamp);

        if (passPrice > failPrice) {
            p.state = State.DecidedPass;
            timelock.scheduleBatch(
                p.targets, p.values, p.calldatas, bytes32(0), p.timelockSalt, timelockDelay
            );
            emit ProposalDecided(proposalId, State.DecidedPass, passPrice, failPrice);
        } else {
            p.state = State.DecidedFail;
            emit ProposalDecided(proposalId, State.DecidedFail, passPrice, failPrice);
        }
    }

    /// @notice Called by Resolver after it reports BCT payouts.
    function markResolved(uint256 proposalId) external {
        require(msg.sender == resolver, "PF: not resolver");
        Proposal storage p = proposals_[proposalId];
        require(p.state == State.DecidedPass || p.state == State.DecidedFail, "PF: not decided");
        p.state = State.Resolved;
        emit ProposalResolved(proposalId);
    }

    // ── Views ─────────────────────────────────────────────────────────────

    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address proposer,
            address passAMM,
            address failAMM,
            bytes32 passConditionId,
            bytes32 failConditionId,
            uint256 tradingDeadline,
            uint256 kpiObservationBlock,
            uint256 kpiLo,
            uint256 kpiHi,
            State state
        )
    {
        Proposal storage p = proposals_[proposalId];
        return (
            p.proposer,
            address(p.passAMM),
            address(p.failAMM),
            p.passConditionId,
            p.failConditionId,
            p.tradingDeadline,
            p.kpiObservationBlock,
            p.kpiLo,
            p.kpiHi,
            p.state
        );
    }

    function getQuestionIds(uint256 proposalId) external view returns (bytes32 passQ, bytes32 failQ) {
        Proposal storage p = proposals_[proposalId];
        return (p.passQuestionId, p.failQuestionId);
    }

    function getKPIConfig(uint256 proposalId)
        external
        view
        returns (address target, address token, uint256 observationBlock, uint256 lo, uint256 hi, State state)
    {
        Proposal storage p = proposals_[proposalId];
        return (p.kpiTarget, p.kpiToken, p.kpiObservationBlock, p.kpiLo, p.kpiHi, p.state);
    }

    function getExecutionPayload(uint256 proposalId)
        external
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 salt)
    {
        Proposal storage p = proposals_[proposalId];
        return (p.targets, p.values, p.calldatas, p.timelockSalt);
    }
}
