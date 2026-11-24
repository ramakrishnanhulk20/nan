// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {HandleRegistry} from "../test/mocks/HandleRegistry.sol";

/// @notice Deploys NameCredit and writes the addresses to deployments/<chain id>.json.
///         On BNB Smart Chain mainnet it uses the real Agent ID registry and nothing else.
///         On BNB testnet, where no Agent ID registry exists, it first deploys a stand-in from the registry's
///         own verified source, owned by the deployer so that test names can be issued.
/// @dev    OWNER is required and becomes the pool owner at once; on mainnet the deploying key keeps no power.
///         Optional: FIRST_ADVANCE_WEI, CAP_WEI, TERM_SECONDS, PACE_PER_DAY.
///         Mainnet: the signing key comes from the command line (--account or --ledger), never from a file.
///         Testnet: signs with SECURITY_TESTNET_KEY, a wallet that only ever holds test BNB.
contract Deploy is Script {
    address internal constant MAINNET_REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    uint256 internal constant BSC_MAINNET = 56;
    uint256 internal constant BSC_TESTNET = 97;

    function run() external returns (NameCredit credit, address registry) {
        address owner = vm.envAddress("OWNER");
        // Checked casts: a mistyped number must stop the deploy, not wrap round to a different setting.
        NameCredit.Settings memory s = NameCredit.Settings({
            firstAdvance: SafeCast.toUint96(vm.envOr("FIRST_ADVANCE_WEI", uint256(0.0003 ether))),
            cap: SafeCast.toUint96(vm.envOr("CAP_WEI", uint256(0.0048 ether))),
            term: SafeCast.toUint32(vm.envOr("TERM_SECONDS", uint256(3 days))),
            pacePerDay: SafeCast.toUint32(vm.envOr("PACE_PER_DAY", uint256(100)))
        });

        require(block.chainid == BSC_MAINNET || block.chainid == BSC_TESTNET, "BNB Smart Chain mainnet or testnet only");
        require(owner != address(0), "OWNER is not set");

        if (block.chainid == BSC_MAINNET) {
            registry = MAINNET_REGISTRY;
            require(registry.code.length != 0, "the Agent ID registry is not at its mainnet address");
            vm.startBroadcast();
        } else {
            uint256 testKey = vm.envUint("SECURITY_TESTNET_KEY");
            vm.startBroadcast(testKey);
            registry = address(new HandleRegistry(vm.addr(testKey), 1, 15, "", ""));
        }
        credit = new NameCredit(registry, owner, s);
        vm.stopBroadcast();

        string memory key = "deployment";
        vm.serializeUint(key, "chainId", block.chainid);
        vm.serializeAddress(key, "registry", registry);
        vm.serializeAddress(key, "owner", owner);
        vm.serializeUint(key, "deployedAtBlock", block.number);
        string memory json = vm.serializeAddress(key, "nameCredit", address(credit));
        vm.writeJson(json, string.concat("deployments/", vm.toString(block.chainid), ".json"));

        console.log("chain id", block.chainid);
        console.log("registry", registry);
        console.log("NameCredit", address(credit));
        console.log("owner", credit.owner());
        console.log("first advance wei", s.firstAdvance);
        console.log("cap wei", s.cap);
        console.log("term seconds", s.term);
        console.log("pace per day", s.pacePerDay);
    }
}
