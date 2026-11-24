// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Reads the attack record that Phase1 and Phase2 left on BNB testnet and prints it. Sends nothing.
// Fails if any attack was not refused, so it can gate a release.
// Run from packages/contracts:  forge script security/Report.s.sol --rpc-url $BSC_TESTNET_RPC_URL

import {Script, console} from "forge-std/Script.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {AttackRunner} from "./AttackRunner.sol";

contract Report is Script {
    function _name(bytes4 reason) internal pure returns (string memory) {
        if (reason == NameCredit.NoAgentId.selector) return "NoAgentId";
        if (reason == NameCredit.NameMismatch.selector) return "NameMismatch";
        if (reason == NameCredit.AdvanceOpen.selector) return "AdvanceOpen";
        if (reason == NameCredit.TooEarly.selector) return "TooEarly";
        if (reason == NameCredit.PaceExhausted.selector) return "PaceExhausted";
        if (reason == NameCredit.PoolEmpty.selector) return "PoolEmpty";
        if (reason == NameCredit.PayoutFailed.selector) return "PayoutFailed";
        if (reason == NameCredit.NothingOwed.selector) return "NothingOwed";
        if (reason == NameCredit.Underpaid.selector) return "Underpaid";
        if (reason == NameCredit.NotOverdue.selector) return "NotOverdue";
        if (reason == NameCredit.AlreadyMarked.selector) return "AlreadyMarked";
        if (reason == NameCredit.NothingScheduled.selector) return "NothingScheduled";
        if (reason == NameCredit.TooSoon.selector) return "TooSoon";
        if (reason == NameCredit.BadPass.selector) return "BadPass";
        if (reason == NameCredit.DirectTransfer.selector) return "DirectTransfer";
        if (reason == NameCredit.RenounceDisabled.selector) return "RenounceDisabled";
        if (reason == Ownable.OwnableUnauthorizedAccount.selector) return "OwnableUnauthorizedAccount";
        if (reason == bytes4(keccak256("BooksUnchanged()"))) return "the totals did not move";
        if (reason == bytes4(0)) return "no such function";
        return "unrecognised error";
    }

    function run() external view {
        require(block.chainid == 97, "the attack record lives on BNB testnet");
        string memory json = vm.readFile("deployments/97-security.json");
        AttackRunner runner = AttackRunner(payable(vm.parseJsonAddress(json, ".runner")));
        AttackRunner.Result[] memory results = runner.results();

        console.log("attack record on chain", block.chainid);
        console.log("runner", address(runner));
        console.log("target", address(runner.CREDIT()));
        console.log("");
        uint256 notRefused;
        for (uint256 i; i < results.length; ++i) {
            AttackRunner.Result memory r = results[i];
            console.log(
                string.concat(r.refused ? "REFUSED  " : "!! WENT THROUGH  ", "[", r.rule, "] ", r.attack, " -> ", _name(r.reason))
            );
            if (!r.refused) ++notRefused;
        }
        console.log("");
        console.log("attacks tried", results.length);
        console.log("attacks refused", results.length - notRefused);
        require(notRefused == 0, "at least one attack was not refused");
    }
}
