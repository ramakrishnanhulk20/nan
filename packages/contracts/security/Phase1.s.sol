// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// SECURITY TEST ONLY. Attacks this project's own NameCredit on BNB testnet and leaves the record on chain.
// Refuses to run on any other chain. Signs only with SECURITY_TESTNET_KEY, a wallet that holds test BNB only.
// Run from packages/contracts:  forge script security/Phase1.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
// Then read the record with:    forge script security/Report.s.sol --rpc-url $BSC_TESTNET_RPC_URL
// What this does NOT cover: attacks that need a day to pass (Phase2.s.sol), a real Agentic Wallet, and
// Binance's own preview and risk check.

import {Script, console} from "forge-std/Script.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {IAgentIdRegistry} from "../src/interfaces/IAgentIdRegistry.sol";
import {HandleRegistry} from "../test/mocks/HandleRegistry.sol";
import {RawRegistry} from "../test/mocks/Hostile.sol";
import {AttackRunner} from "./AttackRunner.sol";

contract Phase1 is Script {
    uint256 internal constant BSC_TESTNET = 97;
    uint256 internal constant PUPPETS = 8;

    NameCredit internal credit;
    HandleRegistry internal registry;
    AttackRunner internal runner;
    RawRegistry internal raw;
    NameCredit internal hostile;
    address internal operator;

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

        vm.startBroadcast(key);
        _setUp();
        _attackThePool();
        _attackThroughTheRegistry();
        vm.stopBroadcast();

        string memory out = "security";
        vm.serializeAddress(out, "runner", address(runner));
        vm.serializeAddress(out, "hostileRegistry", address(raw));
        vm.serializeAddress(out, "hostileCredit", address(hostile));
        vm.serializeUint(out, "lateBorrowerPuppet", 2);
        string memory written = vm.serializeUint(out, "phase1Block", block.number);
        vm.writeJson(written, "deployments/97-security.json");

        console.log("runner", address(runner));
        console.log("attacks recorded", runner.results().length);
    }

    function _setUp() internal {
        runner = new AttackRunner(credit, PUPPETS);
        for (uint256 i; i < PUPPETS; ++i) {
            // Names must be new on every run: a short tag from the block number, then the puppet index.
            string memory name = string.concat("p", vm.toString(block.number % 1_000_000_000), "x", vm.toString(i));
            registry.adminRegister(name, address(runner.puppets(i)));
        }
        if (address(credit).balance < 0.02 ether) credit.topUp{value: 0.02 ether}();
        (bool funded,) = address(runner).call{value: 0.003 ether}("");
        require(funded, "could not fund the runner");
    }

    function _attackThePool() internal {
        bytes32 pass0 = keccak256(abi.encode("phase1", block.number, uint256(0)));
        bytes32 pass1 = keccak256(abi.encode("phase1", block.number, uint256(1)));
        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = keccak256(abi.encode(pass0));
        hashes[1] = keccak256(abi.encode(pass1));
        credit.addPasses(hashes, uint40(block.timestamp + 7 days));

        runner.noNameBorrows(pass1);
        runner.secondAdvance(0, pass0);
        runner.reenterOnPayout(1, pass1);
        runner.spoilAnOpenAdvance(0);
        runner.unwantedBnb();
        runner.ownerFunctions();
        runner.reuseAPass(2, 3, pass1);
        runner.beatThePace(4, PUPPETS);
        runner.climbInAMinute(0);

        runner.rushSettings();
        (uint96 first, uint96 cap, uint32 term, uint32 pace) = credit.settings();
        credit.scheduleSettings(NameCredit.Settings({firstAdvance: first, cap: cap, term: term, pacePerDay: pace}));
        runner.rushSettings();
        credit.cancelSettings();
    }

    function _attackThroughTheRegistry() internal {
        bytes4 balanceOf = IAgentIdRegistry.balanceOf.selector;
        bytes4 handleOf = IAgentIdRegistry.handleOf.selector;
        bytes4 ownerOfHandle = IAgentIdRegistry.ownerOfHandle.selector;

        (uint96 first, uint96 cap, uint32 term, uint32 pace) = credit.settings();
        raw = new RawRegistry();
        hostile = new NameCredit(
            address(raw), operator, NameCredit.Settings({firstAdvance: first, cap: cap, term: term, pacePerDay: pace})
        );
        hostile.topUp{value: 0.001 ether}();

        raw.set(balanceOf, 1, "");
        runner.againstAHostileRegistry(hostile, "the registry reverts when asked who holds a name");

        raw.set(balanceOf, 0, abi.encode(uint256(1)));
        raw.set(handleOf, 0, abi.encode(""));
        runner.againstAHostileRegistry(hostile, "the registry says yes but returns an empty name");

        raw.set(handleOf, 0, abi.encode("someone"));
        raw.set(ownerOfHandle, 0, abi.encode(address(0xdEaD)));
        runner.againstAHostileRegistry(hostile, "the registry says the name belongs to someone else");

        bytes memory long = new bytes(65);
        for (uint256 i; i < 65; ++i) {
            long[i] = "a";
        }
        raw.set(handleOf, 0, abi.encode(string(long)));
        raw.set(ownerOfHandle, 0, abi.encode(address(runner)));
        runner.againstAHostileRegistry(hostile, "the registry returns a name longer than 64 bytes");

        raw.set(balanceOf, 2, "");
        runner.againstAHostileRegistry(hostile, "the registry never answers");

        raw.set(balanceOf, 3, "");
        runner.againstAHostileRegistry(hostile, "the registry floods the caller with data");

        hostile.withdraw(address(hostile).balance);
    }
}
