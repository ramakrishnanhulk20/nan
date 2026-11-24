// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// SECURITY TEST ONLY. The attacks that need time to pass. Run at least 25 hours after Phase1, once the advance
// left open there is past its due time and its day of grace, and within 7 days of it, while the settings
// scheduled there can still be applied. Anyone may apply those settings once their delay has passed; if
// somebody else already has, this script stops before it sends anything and the burst check needs a fresh
// deployment. BNB testnet only.
// Run from packages/contracts:  forge script security/Phase2.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast

import {Script, console} from "forge-std/Script.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {IAgentIdRegistry} from "../src/interfaces/IAgentIdRegistry.sol";
import {RawRegistry} from "../test/mocks/Hostile.sol";
import {AttackRunner} from "./AttackRunner.sol";

contract Phase2 is Script {
    AttackRunner internal runner;
    NameCredit internal credit;
    NameCredit internal hostile;
    RawRegistry internal raw;
    uint256 internal late;

    function run() external {
        require(block.chainid == 97, "security scripts run on BNB testnet only");
        uint256 key = vm.envUint("SECURITY_TESTNET_KEY");

        string memory json = vm.readFile("deployments/97-security.json");
        runner = AttackRunner(payable(vm.parseJsonAddress(json, ".runner")));
        hostile = NameCredit(payable(vm.parseJsonAddress(json, ".hostileCredit")));
        raw = RawRegistry(vm.parseJsonAddress(json, ".hostileRegistry"));
        late = vm.parseJsonUint(json, ".lateBorrowerPuppet");
        credit = runner.CREDIT();

        NameCredit.Standing memory st = credit.standingOf(address(runner.puppets(late)));
        require(st.owed != 0, "the late borrower has no open advance");
        require(block.timestamp > st.overdueAt, "too early: the advance is not past its grace yet");
        uint256 ready = credit.pendingSettingsAt();
        require(ready != 0 && block.timestamp >= ready, "the settings scheduled in phase one are not ready");
        require(block.timestamp <= ready + credit.SETTINGS_WINDOW(), "the settings scheduled in phase one have lapsed");

        uint256 before = runner.results().length;
        vm.startBroadcast(key);
        _lateAndCoolingOff();
        _reserve();
        runner.burstAfterASettingsChange(8, 9);
        _returningBorrower();
        runner.sweep();
        vm.stopBroadcast();

        console.log("entries added", runner.results().length - before);
    }

    function _lateAndCoolingOff() internal {
        bytes32 pass = keccak256(abi.encode("phase2", block.number));
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = keccak256(abi.encode(pass));
        credit.addPasses(hashes, uint40(block.timestamp + 1 hours));
        runner.afterTheGrace(late, pass);
    }

    /// Sets the pool one wei short of what a second-step advance needs: the advance itself plus one day of
    /// first advances.
    function _reserve() internal {
        (uint96 first, uint96 cap,, uint32 pace) = credit.settings();
        uint256 secondStep = 2 * uint256(first) > cap ? cap : 2 * uint256(first);
        uint256 target = secondStep + uint256(pace) * first - 1;
        uint256 balance = address(credit).balance;
        if (balance > target) credit.withdraw(balance - target);
        if (balance < target) credit.topUp{value: target - balance}();
        runner.intoTheReserve(0);
    }

    /// The runner itself borrowed from the second pool in phase one, when its registry answered honestly.
    /// It comes back, and the registry no longer vouches for it.
    function _returningBorrower() internal {
        bytes4 balanceOf = IAgentIdRegistry.balanceOf.selector;
        raw.set(balanceOf, 1, "");
        runner.againstAHostileRegistry(
            hostile, "a returning borrower, once the registry stops answering", "C1", NameCredit.NoAgentId.selector
        );
        raw.set(balanceOf, 0, abi.encode(uint256(1)));
        raw.set(IAgentIdRegistry.handleOf.selector, 0, abi.encode("anothername"));
        raw.set(IAgentIdRegistry.ownerOfHandle.selector, 0, abi.encode(address(runner)));
        runner.againstAHostileRegistry(
            hostile, "a returning borrower whose name has changed", "C1", NameCredit.NameMismatch.selector
        );
    }
}
