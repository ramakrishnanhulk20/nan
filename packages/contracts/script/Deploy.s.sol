// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {HandleRegistry} from "../test/mocks/HandleRegistry.sol";
import {MainnetPlan} from "./Plan.sol";

/// @notice Deploys NameCredit and, when run with --broadcast, writes the addresses to
///         deployments/<chain id>.json. A dry run writes nothing. The file is written before the
///         transactions are confirmed, so if a broadcast fails part-way, delete it: the scripts that read
///         it check the chain first and stop when the address holds no pool.
///         On BNB Smart Chain mainnet it uses the real Agent ID registry and the settings written in Plan.sol.
///         On BNB testnet, where no Agent ID registry exists, it first deploys a stand-in from the registry's
///         own verified source, owned by the deployer so that test names can be issued.
/// @dev    Mainnet needs OWNER and CONFIRM_MAINNET_OWNER set to the same address. The owner is typed twice
///         because it is the one input a typo can ruin. The signing key comes from the command line
///         (--account or --ledger), never from a file, and keeps no power afterwards. The four settings
///         cannot be changed from the environment on mainnet: a value left over from a testnet run must not
///         reach a pool that holds real money.
///         Testnet signs with SECURITY_TESTNET_KEY, a wallet that only ever holds test BNB, and accepts
///         FIRST_ADVANCE_WEI, CAP_WEI, TERM_SECONDS and PACE_PER_DAY so the attack scripts can use a short term.
contract Deploy is Script, MainnetPlan {
    /// @dev This project's testnet-only wallet. Its key sits in a file, so it must never own a mainnet pool.
    ///      Written here so the check does not depend on the environment being loaded.
    address internal constant TESTNET_ONLY_WALLET = 0xF6010Cf5E9d5a33531ae0479c33aA48d958eFfA5;
    uint256 internal constant BSC_TESTNET = 97;

    function run() external returns (NameCredit credit, address registry) {
        require(block.chainid == BSC_MAINNET || block.chainid == BSC_TESTNET, "BNB Smart Chain mainnet or testnet only");
        address owner = vm.envAddress("OWNER");
        require(owner != address(0), "OWNER is not set");
        NameCredit.Settings memory s =
            NameCredit.Settings({firstAdvance: FIRST_ADVANCE, cap: CAP, term: TERM, pacePerDay: PACE_PER_DAY});

        if (block.chainid == BSC_MAINNET) {
            require(
                !vm.envExists("FIRST_ADVANCE_WEI") && !vm.envExists("CAP_WEI") && !vm.envExists("TERM_SECONDS")
                    && !vm.envExists("PACE_PER_DAY"),
                "mainnet uses the settings written in this script: unset FIRST_ADVANCE_WEI, CAP_WEI, TERM_SECONDS and PACE_PER_DAY"
            );
            require(
                owner != TESTNET_ONLY_WALLET && owner != vm.envOr("SECURITY_TESTNET_ADDRESS", address(0)),
                "OWNER is the testnet-only wallet, which must never own a mainnet pool"
            );
            require(
                owner == vm.envOr("CONFIRM_MAINNET_OWNER", address(0)), "set CONFIRM_MAINNET_OWNER to the same address as OWNER"
            );
            registry = MAINNET_REGISTRY;
            require(registry.code.length != 0, "the Agent ID registry is not at its mainnet address");
            vm.startBroadcast();
        } else {
            // Checked casts: a mistyped number must stop the deploy, not wrap round to a different setting.
            s.firstAdvance = SafeCast.toUint96(vm.envOr("FIRST_ADVANCE_WEI", uint256(FIRST_ADVANCE)));
            s.cap = SafeCast.toUint96(vm.envOr("CAP_WEI", uint256(CAP)));
            s.term = SafeCast.toUint32(vm.envOr("TERM_SECONDS", uint256(TERM)));
            s.pacePerDay = SafeCast.toUint32(vm.envOr("PACE_PER_DAY", uint256(PACE_PER_DAY)));
            uint256 testKey = vm.envUint("SECURITY_TESTNET_KEY");
            vm.startBroadcast(testKey);
            // The same name lengths as the real registry allows, 3 to 20.
            registry = address(new HandleRegistry(vm.addr(testKey), 3, 20, "", ""));
        }
        credit = new NameCredit(registry, owner, s);
        vm.stopBroadcast();

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            string memory key = "deployment";
            vm.serializeUint(key, "chainId", block.chainid);
            vm.serializeAddress(key, "registry", registry);
            vm.serializeAddress(key, "owner", owner);
            // The block the script simulated on, a few before the one the deployment landed in. Safe as a
            // place to start reading logs from.
            vm.serializeUint(key, "logsFromBlock", block.number);
            string memory json = vm.serializeAddress(key, "nameCredit", address(credit));
            vm.writeJson(json, string.concat("deployments/", vm.toString(block.chainid), ".json"));
        } else {
            console.log("DRY RUN: nothing was sent and no deployment file was written");
        }

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
