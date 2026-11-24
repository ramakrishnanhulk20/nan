// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {MainnetPlan} from "./Plan.sol";

/// @notice Reads a live deployment and says whether it is the one that was published. Sends nothing and
///         needs no key.
/// @dev    Run from packages/contracts:
///           forge script script/Check.s.sol --rpc-url https://bsc-rpc.publicnode.com
///         It reads the address from deployments/<chain id>.json and the facts from the chain. On mainnet it
///         fails unless the pool reads the real Agent ID registry and is owned by the address in the file.
///         It prints the four settings next to the planned ones; they differ only if the owner has changed
///         them since, which is a public event (SettingsApplied) and is said plainly in the output.
contract Check is Script, MainnetPlan {
    function run() external view {
        string memory json = vm.readFile(string.concat("deployments/", vm.toString(block.chainid), ".json"));
        address pool = vm.parseJsonAddress(json, ".nameCredit");
        address recordedOwner = vm.parseJsonAddress(json, ".owner");
        address recordedRegistry = vm.parseJsonAddress(json, ".registry");
        require(pool.code.length != 0, "there is no contract at the address in the deployment file");

        NameCredit credit = NameCredit(payable(pool));
        (uint96 first, uint96 cap, uint32 term, uint32 pace) = credit.settings();
        bool asPlanned = first == FIRST_ADVANCE && cap == CAP && term == TERM && pace == PACE_PER_DAY;

        console.log("chain id", block.chainid);
        console.log("NameCredit", pool);
        console.log("code size in bytes", pool.code.length);
        console.log("registry it reads", address(credit.REGISTRY()));
        console.log("owner", credit.owner());
        console.log("first advance wei", first);
        console.log("cap wei", cap);
        console.log("term seconds", term);
        console.log("pace per day", pace);
        console.log("new advances paused", credit.paused());
        console.log("a settings change is scheduled", credit.pendingSettingsAt() != 0);
        console.log("pool balance wei", pool.balance);

        require(address(credit.REGISTRY()) == recordedRegistry, "the registry on chain is not the one in the deployment file");
        require(credit.owner() == recordedOwner, "the owner on chain is not the one in the deployment file");
        if (block.chainid == BSC_MAINNET) {
            require(address(credit.REGISTRY()) == MAINNET_REGISTRY, "this pool does not read the real Agent ID registry");
            console.log(
                asPlanned
                    ? "CHECKED: the real Agent ID registry, the recorded owner, and the four settings as planned."
                    : "CHECKED: the real Agent ID registry and the recorded owner. The settings have been changed since deployment."
            );
        } else {
            console.log("CHECKED: the registry and owner match the deployment file. This is not mainnet, so the settings are not compared with the mainnet plan.");
        }
    }
}
