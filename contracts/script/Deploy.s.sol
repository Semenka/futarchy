// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {BinaryConditionalTokens} from "../src/BinaryConditionalTokens.sol";
import {ProposalFactory} from "../src/ProposalFactory.sol";
import {Resolver} from "../src/Resolver.sol";
import {MockERC20} from "../test/MockERC20.sol";

/// @notice Deploys the futarchy stack + a mock USDC collateral token +
///         funds the Timelock (treasury) with 100 native ETH. Roles wired
///         so ProposalFactory can schedule batches and anyone can execute.
contract Deploy is Script {
    uint256 constant TIMELOCK_DELAY = 5 minutes; // short for demo
    uint256 constant TREASURY_SEED = 100 ether;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        MockERC20 usdc = new MockERC20("Futarchy USDC", "fUSDC");
        BinaryConditionalTokens bct = new BinaryConditionalTokens();

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        TimelockController timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, deployer);

        // Resolver address must be known before factory deploys (factory stores it immutably).
        // We compute CREATE address: resolver is the 4th contract deployed from `deployer`.
        address resolverAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        ProposalFactory factory =
            new ProposalFactory(IERC20(address(usdc)), bct, timelock, resolverAddr, TIMELOCK_DELAY);
        Resolver resolver = new Resolver(bct, factory);
        require(address(resolver) == resolverAddr, "resolver addr mismatch");

        // Grant PROPOSER role to factory; drop deployer admin.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(factory));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // Seed collateral to deployer so they can mint for demo traders.
        usdc.mint(deployer, 1_000_000 ether);

        // Fund the treasury with ETH
        (bool ok,) = address(timelock).call{value: TREASURY_SEED}("");
        require(ok, "treasury funding failed");

        vm.stopBroadcast();

        console2.log("fUSDC         ", address(usdc));
        console2.log("BCT           ", address(bct));
        console2.log("Timelock      ", address(timelock));
        console2.log("ProposalFactory", address(factory));
        console2.log("Resolver      ", address(resolver));
    }
}
