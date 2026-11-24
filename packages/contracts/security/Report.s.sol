// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Reads the record that Phase1 and Phase2 left on BNB testnet and prints it. Sends nothing and needs no key.
// Every entry carries the error the rule under test says it must be refused with. This script fails unless
// every attack was refused with exactly that error and every control went through.
// Run from packages/contracts:
//   forge script security/Report.s.sol --rpc-url https://bsc-testnet-dataseed.bnbchain.org

import {Script, console} from "forge-std/Script.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
        if (reason == NameCredit.SettingsLapsed.selector) return "SettingsLapsed";
        if (reason == NameCredit.BadPass.selector) return "BadPass";
        if (reason == NameCredit.PassNotNeeded.selector) return "PassNotNeeded";
        if (reason == NameCredit.BatchTooLarge.selector) return "BatchTooLarge";
        if (reason == NameCredit.DirectTransfer.selector) return "DirectTransfer";
        if (reason == NameCredit.RenounceDisabled.selector) return "RenounceDisabled";
        if (reason == Ownable.OwnableUnauthorizedAccount.selector) return "OwnableUnauthorizedAccount";
        if (reason == ReentrancyGuard.ReentrancyGuardReentrantCall.selector) return "ReentrancyGuardReentrantCall";
        if (reason == bytes4(keccak256("BooksBalance()"))) return "the books balance";
        if (reason == bytes4(keccak256("CostTooMuch()"))) return "cost more gas than three capped reads";
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
        uint256 attacks;
        uint256 attacksWrong;
        uint256 controls;
        uint256 controlsWrong;
        for (uint256 i; i < results.length; ++i) {
            AttackRunner.Result memory r = results[i];
            bool control = keccak256(bytes(r.rule)) == keccak256("control");
            string memory line;
            if (control) {
                ++controls;
                if (!r.asExpected) ++controlsWrong;
                line = string.concat(r.asExpected ? "SERVED   " : "!! CONTROL FAILED  ", "[control] ", r.attack);
                if (!r.asExpected) line = string.concat(line, " -> ", _name(r.reason));
            } else {
                ++attacks;
                if (!r.asExpected) ++attacksWrong;
                line = string.concat(
                    r.asExpected ? (r.expected == bytes4(keccak256("BooksBalance()")) ? "HOLDS    " : "REFUSED  ") : (r.refused ? "!! REFUSED FOR THE WRONG REASON  " : "!! WENT THROUGH  "),
                    "[",
                    r.rule,
                    "] ",
                    r.attack,
                    " -> ",
                    r.refused ? _name(r.reason) : "served"
                );
                if (!r.asExpected) line = string.concat(line, " (expected ", _name(r.expected), ")");
            }
            console.log(line);
        }
        console.log("");
        console.log("attacks tried", attacks);
        console.log("attacks refused with the expected error", attacks - attacksWrong);
        console.log("controls that had to succeed", controls);
        console.log("controls that succeeded", controls - controlsWrong);
        require(attacksWrong == 0 && controlsWrong == 0, "at least one entry was not as expected");
    }
}
