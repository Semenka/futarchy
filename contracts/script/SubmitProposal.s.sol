// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ProposalFactory} from "../src/ProposalFactory.sol";

/// @notice Submit a demo grant proposal: transfer 0.025 ETH from treasury → 0xdEAD…0000.
///         Short trading window for tight demo pacing.
contract SubmitProposal is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_KEY");
        address sender = vm.addr(pk);

        address factoryAddr = vm.envAddress("FACTORY_ADDRESS");
        address usdcAddr = vm.envAddress("USDC_ADDRESS");
        address timelockAddr = vm.envAddress("TIMELOCK_ADDRESS");
        address grantee = vm.envAddress("GRANTEE_ADDRESS");
        uint256 grantAmount = vm.envUint("GRANT_AMOUNT");
        uint256 tradingWindow = vm.envUint("TRADING_WINDOW");
        uint256 observationBlocks = vm.envUint("OBSERVATION_BLOCKS");
        uint256 kpiHi = vm.envUint("KPI_HI");
        uint256 seed = vm.envUint("SEED_COLLATERAL");

        ProposalFactory factory = ProposalFactory(factoryAddr);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = grantee;
        values[0] = grantAmount;
        calldatas[0] = "";

        ProposalFactory.CreateParams memory params = ProposalFactory.CreateParams({
            targets: targets,
            values: values,
            calldatas: calldatas,
            tradingWindow: tradingWindow,
            observationDelayBlocks: observationBlocks,
            kpiLo: 0,
            kpiHi: kpiHi,
            seedCollateral: seed,
            kpiTarget: timelockAddr,
            kpiToken: address(0)
        });

        vm.startBroadcast(pk);
        IERC20(usdcAddr).approve(factoryAddr, seed * 6);
        uint256 id = factory.createProposal(params);
        vm.stopBroadcast();

        console2.log("submitted proposal id =", id);
        console2.log("sender               ", sender);
        console2.log("grantee              ", grantee);
        console2.log("grant (wei)          ", grantAmount);
    }
}
