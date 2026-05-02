// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {BinaryConditionalTokens} from "../src/BinaryConditionalTokens.sol";
import {ProposalFactory} from "../src/ProposalFactory.sol";
import {Resolver} from "../src/Resolver.sol";
import {MockERC20} from "../test/MockERC20.sol";

/// @notice Deploys the futarchy stack + a mock USDC collateral + funds the
///         Timelock (treasury) with a small native-ETH balance for demo proposals.
///         Mints fUSDC to the deployer and the three demo agent personas so they
///         can immediately start trading without needing a separate fund step.
contract Deploy is Script {
    uint256 constant TIMELOCK_DELAY = 5 minutes;
    uint256 constant TREASURY_SEED = 0.05 ether;
    uint256 constant DEPLOYER_USDC = 1_000_000 ether;
    uint256 constant AGENT_USDC = 10_000 ether;

    // Agent personas (hard-coded for demo).
    address constant BULLISH = 0xCcb98ae5cd6BeAa40c308AAd4dCf6308f5DdBEEF;
    address constant BEARISH = 0x1a910206F8620F4C205E51881C3525cd2269c9A5;
    address constant CONTRARIAN = 0xCDc04eCA16EFFa1f57DA4e435a4a90d5eA1d02fd;

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
        address resolverAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        ProposalFactory factory =
            new ProposalFactory(IERC20(address(usdc)), bct, timelock, resolverAddr, TIMELOCK_DELAY);
        Resolver resolver = new Resolver(bct, factory);
        require(address(resolver) == resolverAddr, "resolver addr mismatch");

        // Grant PROPOSER role to factory; drop deployer admin.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(factory));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // Mint fUSDC: deployer (proposer + LP) + each agent persona.
        usdc.mint(deployer, DEPLOYER_USDC);
        usdc.mint(BULLISH, AGENT_USDC);
        usdc.mint(BEARISH, AGENT_USDC);
        usdc.mint(CONTRARIAN, AGENT_USDC);

        // Fund the treasury (timelock) with a small native-ETH balance for demo proposals.
        if (TREASURY_SEED > 0) {
            (bool ok,) = address(timelock).call{value: TREASURY_SEED}("");
            require(ok, "treasury funding failed");
        }

        vm.stopBroadcast();

        console2.log("fUSDC          ", address(usdc));
        console2.log("BCT            ", address(bct));
        console2.log("Timelock       ", address(timelock));
        console2.log("ProposalFactory", address(factory));
        console2.log("Resolver       ", address(resolver));
    }
}
