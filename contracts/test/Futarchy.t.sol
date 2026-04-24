// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {BinaryConditionalTokens} from "../src/BinaryConditionalTokens.sol";
import {ERC1155Wrapper} from "../src/ERC1155Wrapper.sol";
import {FutarchyAMM} from "../src/FutarchyAMM.sol";
import {ProposalFactory} from "../src/ProposalFactory.sol";
import {Resolver} from "../src/Resolver.sol";
import {MockERC20} from "./MockERC20.sol";

contract FutarchyTest is Test, ERC1155Holder {
    BinaryConditionalTokens bct;
    MockERC20 usdc;
    TimelockController timelock;
    Resolver resolver;
    ProposalFactory factory;

    address proposer = address(0xA11CE);
    address alice = address(0xA);
    address bob = address(0xB); // grantee
    address whale = address(0xBEEF); // big trader

    uint256 constant TIMELOCK_DELAY = 1 hours;
    uint256 constant TRADING_WINDOW = 1 days;
    uint256 constant OBSERVATION_DELAY_BLOCKS = 100;
    uint256 constant SEED = 100 ether;

    function setUp() public {
        bct = new BinaryConditionalTokens();
        usdc = new MockERC20("Mock USDC", "mUSDC");

        address[] memory proposers = new address[](0); // granted later
        address[] memory executors = new address[](1);
        executors[0] = address(0); // permissionless execute
        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, address(this));

        // Deploy factory + resolver in two passes because they reference each other
        address resolverAddr = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        factory = new ProposalFactory(IERC20(address(usdc)), bct, timelock, resolverAddr, TIMELOCK_DELAY);
        resolver = new Resolver(bct, factory);
        require(address(resolver) == resolverAddr, "resolver addr mismatch");

        // Grant PROPOSER_ROLE to factory
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(factory));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        // Fund the timelock (treasury) with 100 ETH
        vm.deal(address(timelock), 100 ether);

        // Mint collateral to proposer + traders
        usdc.mint(proposer, 10_000 ether);
        usdc.mint(alice, 10_000 ether);
        usdc.mint(whale, 1_000_000 ether);
    }

    function _createGrantProposal() internal returns (uint256 proposalId) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = bob;
        values[0] = 50 ether; // 50 ETH grant
        calldatas[0] = ""; // plain ETH transfer

        ProposalFactory.CreateParams memory params = ProposalFactory.CreateParams({
            targets: targets,
            values: values,
            calldatas: calldatas,
            tradingWindow: TRADING_WINDOW,
            observationDelayBlocks: OBSERVATION_DELAY_BLOCKS,
            kpiLo: 0,
            kpiHi: 200 ether,
            seedCollateral: SEED,
            kpiTarget: address(timelock),
            kpiToken: address(0) // native ETH
        });

        vm.startPrank(proposer);
        usdc.approve(address(factory), SEED * 3 * 2); // 3x per branch, 2 branches
        proposalId = factory.createProposal(params);
        vm.stopPrank();
    }

    function test_CreateProposal_InitialState() public {
        uint256 id = _createGrantProposal();
        (, address passAMM, address failAMM,,, uint256 deadline,,,, ProposalFactory.State state) = factory.getProposal(id);
        assertEq(uint256(state), uint256(ProposalFactory.State.Trading));
        assertEq(deadline, block.timestamp + TRADING_WINDOW);

        // Both AMMs seeded: SEED collateral + 2*SEED long → spot price ~0.5e18
        uint256 passPrice = FutarchyAMM(passAMM).getLongPrice();
        uint256 failPrice = FutarchyAMM(failAMM).getLongPrice();
        assertApproxEqAbs(passPrice, 0.5e18, 1e15);
        assertApproxEqAbs(failPrice, 0.5e18, 1e15);
    }

    function _pushPrice(FutarchyAMM amm, address trader, uint256 collateralIn) internal {
        vm.startPrank(trader);
        usdc.approve(address(amm), collateralIn);
        amm.swapCollateralForLong(collateralIn, 0, trader);
        vm.stopPrank();
    }

    function test_PassWins_TimelockExecutes_AndResolves() public {
        uint256 id = _createGrantProposal();
        (,address passAMM, address failAMM,,,,,,,) = factory.getProposal(id);

        // Whale pushes pass price UP (buys LONG in pass branch)
        _pushPrice(FutarchyAMM(passAMM), whale, 200 ether);
        // And pushes fail price DOWN by selling LONG: easiest is to mint LONG via split, wrap, sell.
        // Simpler: just buy less / do nothing on fail branch → fail price stays at 0.5, pass rises.

        assertGt(FutarchyAMM(passAMM).getLongPrice(), FutarchyAMM(failAMM).getLongPrice());

        // Advance past trading window so TWAP has nonzero elapsed time
        vm.warp(block.timestamp + TRADING_WINDOW + 1);
        factory.decide(id);

        (,,,,,,,,,ProposalFactory.State state) = factory.getProposal(id);
        assertEq(uint256(state), uint256(ProposalFactory.State.DecidedPass));

        // Advance past timelock delay, execute the batch
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 salt) =
            factory.getExecutionPayload(id);
        uint256 treasuryBefore = address(timelock).balance;
        uint256 bobBefore = bob.balance;
        timelock.executeBatch(targets, values, calldatas, bytes32(0), salt);
        assertEq(address(timelock).balance, treasuryBefore - 50 ether);
        assertEq(bob.balance, bobBefore + 50 ether);

        // Advance past observation block
        vm.roll(block.number + OBSERVATION_DELAY_BLOCKS + 1);

        resolver.resolve(id);
        (,,,,,,,,,state) = factory.getProposal(id);
        assertEq(uint256(state), uint256(ProposalFactory.State.Resolved));

        // KPI = 50 ETH (after transfer), lo=0, hi=200 → numYes = 2500
        (bytes32 passQ, bytes32 failQ) = factory.getQuestionIds(id);
        bytes32 passConditionId = bct.getConditionId(address(resolver), passQ);
        bytes32 failConditionId = bct.getConditionId(address(resolver), failQ);

        (,,,, uint128 passNum1, uint128 passDenom) = bct.conditions(passConditionId);
        assertEq(passNum1, 2500);
        assertEq(passDenom, 10_000);

        // Fail branch voided
        (,,,uint128 failNum0, uint128 failNum1, uint128 failDenom) = bct.conditions(failConditionId);
        assertEq(failNum0, 5000);
        assertEq(failNum1, 5000);
        assertEq(failDenom, 10_000);
    }

    function test_FailWins_NoExecution() public {
        uint256 id = _createGrantProposal();
        (,address passAMM, address failAMM,,,,,,,) = factory.getProposal(id);

        // Whale pushes FAIL price UP instead
        _pushPrice(FutarchyAMM(failAMM), whale, 200 ether);
        assertGt(FutarchyAMM(failAMM).getLongPrice(), FutarchyAMM(passAMM).getLongPrice());

        vm.warp(block.timestamp + TRADING_WINDOW + 1);
        factory.decide(id);
        (,,,,,,,,,ProposalFactory.State state) = factory.getProposal(id);
        assertEq(uint256(state), uint256(ProposalFactory.State.DecidedFail));

        // Treasury untouched
        assertEq(address(timelock).balance, 100 ether);

        vm.roll(block.number + OBSERVATION_DELAY_BLOCKS + 1);
        resolver.resolve(id);
    }

    /// @notice Fuzz: whoever's branch has a larger push wins. Require a
    ///         non-trivial spread to avoid integer-rounding equalization.
    function testFuzz_HigherPushExecutes(uint96 passPush, uint96 failPush) public {
        passPush = uint96(bound(passPush, 1 ether, 500 ether));
        failPush = uint96(bound(failPush, 1 ether, 500 ether));
        uint256 diff = passPush > failPush ? passPush - failPush : failPush - passPush;
        vm.assume(diff > 0.5 ether);

        uint256 id = _createGrantProposal();
        (,address passAMM, address failAMM,,,,,,,) = factory.getProposal(id);

        _pushPrice(FutarchyAMM(passAMM), whale, passPush);
        _pushPrice(FutarchyAMM(failAMM), whale, failPush);

        vm.warp(block.timestamp + TRADING_WINDOW + 1);
        factory.decide(id);

        (,,,,,,,,,ProposalFactory.State state) = factory.getProposal(id);
        if (passPush > failPush) {
            assertEq(uint256(state), uint256(ProposalFactory.State.DecidedPass));
        } else {
            assertEq(uint256(state), uint256(ProposalFactory.State.DecidedFail));
        }
    }

    function test_SplitMergeRoundTrip() public {
        bytes32 questionId = bytes32(uint256(1));
        bytes32 conditionId = bct.prepareCondition(address(this), questionId);

        usdc.mint(address(this), 100 ether);
        usdc.approve(address(bct), 100 ether);
        bct.splitPosition(IERC20(address(usdc)), conditionId, 100 ether);

        uint256 noId = bct.getPositionId(conditionId, bct.INDEX_NO());
        uint256 yesId = bct.getPositionId(conditionId, bct.INDEX_YES());
        assertEq(IERC1155(address(bct)).balanceOf(address(this), noId), 100 ether);
        assertEq(IERC1155(address(bct)).balanceOf(address(this), yesId), 100 ether);

        bct.mergePositions(IERC20(address(usdc)), conditionId, 100 ether);
        assertEq(usdc.balanceOf(address(this)), 100 ether);
    }

    function test_VoidResolutionRedeemsAtHalf() public {
        bytes32 questionId = bytes32(uint256(42));
        bytes32 conditionId = bct.prepareCondition(address(this), questionId);

        usdc.mint(alice, 100 ether);
        vm.startPrank(alice);
        usdc.approve(address(bct), 100 ether);
        bct.splitPosition(IERC20(address(usdc)), conditionId, 100 ether);
        vm.stopPrank();

        // Report void
        bct.reportPayouts(questionId, 5000, 5000, 10_000);

        vm.startPrank(alice);
        uint256[] memory indexSets = new uint256[](2);
        indexSets[0] = bct.INDEX_NO();
        indexSets[1] = bct.INDEX_YES();
        bct.redeemPositions(IERC20(address(usdc)), conditionId, indexSets);
        vm.stopPrank();

        // Alice started with 10_000 (setUp) + 100 minted here = 10_100, spent 100 on split,
        // got 100 back on void redemption (50 from YES @0.5 + 50 from NO @0.5)
        assertEq(usdc.balanceOf(alice), 10_100 ether);
    }

    receive() external payable {}
}
