// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// SECURITY TEST ONLY. Attacks this project's own NameCredit on BNB testnet and leaves the record on chain.
// Refuses to run on any other chain. Signs only with SECURITY_TESTNET_KEY, a wallet that holds test BNB only.
// Run once per deployment, from packages/contracts:
//   forge script security/Phase1.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
// Then read the record with:
//   forge script security/Report.s.sol --rpc-url $BSC_TESTNET_RPC_URL
// What this does NOT cover: attacks that need a day to pass (Phase2.s.sol), a real Agentic Wallet, and
// Binance's own preview and risk check.

import {Script, console} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {IAgentIdRegistry} from "../src/interfaces/IAgentIdRegistry.sol";
import {HandleRegistry} from "../test/mocks/HandleRegistry.sol";
import {RawRegistry} from "../test/mocks/Hostile.sol";
import {AttackRunner} from "./AttackRunner.sol";

contract Phase1 is Script {
    uint256 internal constant BSC_TESTNET = 97;
    uint256 internal constant PUPPETS = 10;
    uint256 internal constant LATE_BORROWER = 6;
    bytes4 internal constant NO_AGENT_ID = bytes4(keccak256("NoAgentId()"));

    NameCredit internal credit;
    HandleRegistry internal registry;
    AttackRunner internal runner;
    RawRegistry internal raw;
    NameCredit internal hostile;
    address internal operator;
    bytes32[5] internal passes;

    function run() external {
        require(block.chainid == BSC_TESTNET, "security scripts run on BNB testnet only");
        uint256 key = vm.envUint("SECURITY_TESTNET_KEY");
        operator = vm.addr(key);

        string memory json = vm.readFile("deployments/97.json");
        credit = NameCredit(payable(vm.parseJsonAddress(json, ".nameCredit")));
        registry = HandleRegistry(vm.parseJsonAddress(json, ".registry"));
        require(credit.owner() == operator, "the testnet pool must be owned by the security wallet");
        require(registry.owner() == operator, "the stand-in registry must be owned by the security wallet");
        require(address(credit.REGISTRY()) == address(registry), "deployment file does not match the chain");
        require(credit.totals().people == 0, "phase one runs once, on a pool nobody has borrowed from");
        (,,, uint32 pace) = credit.settings();
        require(pace == 24, "phase one expects the testnet pace of 24 a day: one first advance in the store");

        vm.startBroadcast(key);
        _setUp();
        _attackThePool();
        _attackThroughTheRegistry();
        vm.stopBroadcast();

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            string memory out = "security";
            vm.serializeAddress(out, "runner", address(runner));
            vm.serializeAddress(out, "hostileRegistry", address(raw));
            vm.serializeAddress(out, "hostileCredit", address(hostile));
            vm.serializeUint(out, "lateBorrowerPuppet", LATE_BORROWER);
            string memory written = vm.serializeUint(out, "phase1Block", block.number);
            vm.writeJson(written, "deployments/97-security.json");
        } else {
            console.log("dry run: nothing was sent and no file was written");
        }

        console.log("runner", address(runner));
        console.log("entries recorded", runner.results().length);
    }

    function _setUp() internal {
        runner = new AttackRunner(credit, PUPPETS);
        for (uint256 i; i < PUPPETS; ++i) {
            // Names must be new on every run: a short tag from the block number, then the puppet index.
            string memory name = string.concat("p", vm.toString(block.number % 1_000_000_000), "x", vm.toString(i));
            registry.adminRegister(name, address(runner.puppets(i)));
        }
        if (address(credit).balance < 0.02 ether) credit.topUp{value: 0.02 ether}();
        (bool funded,) = address(runner).call{value: 0.002 ether}("");
        require(funded, "could not fund the runner");

        bytes32[] memory hashes = new bytes32[](passes.length);
        for (uint256 i; i < passes.length; ++i) {
            passes[i] = keccak256(abi.encode("phase1", block.number, i));
            hashes[i] = keccak256(abi.encode(passes[i]));
        }
        credit.addPasses(hashes, uint40(block.timestamp + 7 days));
    }

    function _attackThePool() internal {
        runner.noNameBorrows(passes[4]);
        runner.paceServesOneThenRefuses(0, 1);
        runner.againstAnOpenAdvance(0);
        runner.reenterOnPayout(2, [passes[0], passes[1], passes[2]]);
        runner.reenterOnRefund(5, 0);
        runner.climbInAMinute(0, passes[4]);
        runner.reuseAPass(LATE_BORROWER, 7, passes[3]);
        runner.unwantedBnb(0);
        runner.ownerFunctions();
        runner.tooManyAtOnce();

        runner.rushSettings();
        // Left scheduled on purpose: phase two brings it into force and checks that a faster pace does not
        // hand out a burst.
        (uint96 first, uint96 cap, uint32 term, uint32 pace) = credit.settings();
        credit.scheduleSettings(NameCredit.Settings({firstAdvance: first, cap: cap, term: term, pacePerDay: pace * 2}));
        runner.rushSettings();
    }

    function _attackThroughTheRegistry() internal {
        bytes4 balanceOf = IAgentIdRegistry.balanceOf.selector;
        bytes4 handleOf = IAgentIdRegistry.handleOf.selector;
        bytes4 ownerOfHandle = IAgentIdRegistry.ownerOfHandle.selector;
        // 40 bytes, so that an honest answer fills all 128 bytes the pool is willing to read and a flood
        // that opens with it can only be refused for its size.
        string memory name = "a40bytenameaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        bytes memory one = abi.encode(uint256(1));
        bytes memory nameAnswer = abi.encode(name);
        bytes memory ownerAnswer = abi.encode(address(runner));

        (uint96 first, uint96 cap, uint32 term, uint32 pace) = credit.settings();
        raw = new RawRegistry();
        hostile = new NameCredit(
            address(raw), operator, NameCredit.Settings({firstAdvance: first, cap: cap, term: term, pacePerDay: pace})
        );
        hostile.topUp{value: 0.001 ether}();

        raw.set(balanceOf, 1, "");
        runner.againstAHostileRegistry(hostile, "the registry reverts when asked who holds a name", "C1", NO_AGENT_ID);

        raw.set(balanceOf, 0, one);
        raw.set(handleOf, 0, abi.encode(""));
        raw.set(ownerOfHandle, 0, ownerAnswer);
        runner.againstAHostileRegistry(hostile, "the registry says yes but returns an empty name", "C1", NO_AGENT_ID);

        raw.set(handleOf, 0, nameAnswer);
        raw.set(ownerOfHandle, 0, abi.encode(address(0xdEaD)));
        runner.againstAHostileRegistry(hostile, "the registry says the name belongs to someone else", "C1", NO_AGENT_ID);

        bytes memory long = new bytes(65);
        for (uint256 i; i < 65; ++i) {
            long[i] = "a";
        }
        raw.set(handleOf, 0, abi.encode(string(long)));
        raw.set(ownerOfHandle, 0, ownerAnswer);
        runner.againstAHostileRegistry(hostile, "the registry returns a name longer than 64 bytes", "C1", NO_AGENT_ID);

        // From here every answer but one is honest, so the one that stalls or floods is what gets refused.
        raw.set(handleOf, 0, nameAnswer);
        raw.set(balanceOf, 2, "");
        runner.againstAHostileRegistry(hostile, "the first read never answers", "C2", NO_AGENT_ID);
        raw.set(balanceOf, 3, one);
        runner.againstAHostileRegistry(hostile, "the first read answers correctly, then floods", "C2", NO_AGENT_ID);
        raw.set(balanceOf, 0, one);

        raw.set(handleOf, 2, "");
        runner.againstAHostileRegistry(hostile, "the second read never answers", "C2", NO_AGENT_ID);
        raw.set(handleOf, 3, nameAnswer);
        runner.againstAHostileRegistry(hostile, "the second read answers correctly, then floods", "C2", NO_AGENT_ID);
        raw.set(handleOf, 0, nameAnswer);

        raw.set(ownerOfHandle, 2, "");
        runner.againstAHostileRegistry(hostile, "the third read never answers", "C2", NO_AGENT_ID);
        raw.set(ownerOfHandle, 3, ownerAnswer);
        runner.againstAHostileRegistry(hostile, "the third read answers correctly, then floods", "C2", NO_AGENT_ID);
        raw.set(ownerOfHandle, 0, ownerAnswer);

        runner.hostileRegistryControl(hostile);
        hostile.withdraw(address(hostile).balance);
    }
}
