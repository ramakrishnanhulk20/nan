// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// SECURITY TEST ONLY. The attacks that need time to pass: run at least 25 hours after Phase1, once the
// advance left open there is past its due time and its day of grace. BNB testnet only.
// Run from packages/contracts:  forge script security/Phase2.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast

import {Script, console} from "forge-std/Script.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {AttackRunner} from "./AttackRunner.sol";

contract Phase2 is Script {
    function run() external {
        require(block.chainid == 97, "security scripts run on BNB testnet only");
        uint256 key = vm.envUint("SECURITY_TESTNET_KEY");

        string memory json = vm.readFile("deployments/97-security.json");
        AttackRunner runner = AttackRunner(payable(vm.parseJsonAddress(json, ".runner")));
        uint256 late = vm.parseJsonUint(json, ".lateBorrowerPuppet");
        NameCredit credit = runner.CREDIT();

        NameCredit.Standing memory st = credit.standingOf(address(runner.puppets(late)));
        require(st.owed != 0, "the late borrower has no open advance");
        require(block.timestamp > st.overdueAt, "too early: the advance is not past its grace yet");

        uint256 before = runner.results().length;
        vm.startBroadcast(key);
        runner.afterTheGrace(late);
        runner.sweep();
        vm.stopBroadcast();

        console.log("late-payment attacks added", runner.results().length - before);
    }
}
