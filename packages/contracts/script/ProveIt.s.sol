// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {HandleRegistry} from "../test/mocks/HandleRegistry.sol";
import {Puppet} from "../security/AttackRunner.sol";

/// @notice One command that shows the whole promise on BNB testnet with real transactions: a wallet with a
///         name borrows with nothing locked, repays, and moves up a step; a wallet with no name is refused.
/// @dev    Run from packages/contracts:
///           forge script script/ProveIt.s.sol --rpc-url $BSC_TESTNET_RPC_URL --broadcast
///         Signs with SECURITY_TESTNET_KEY. Each run uses a new wallet and a new name, so it can be repeated.
///         What it does NOT show: a real Agentic Wallet, and the real registry. Those are mainnet only.
contract ProveIt is Script {
    NameCredit internal credit;
    HandleRegistry internal registry;
    Puppet internal borrower;
    Puppet internal stranger;

    uint256 internal amount;
    uint256 internal held;
    uint256 internal poolWentDownBy;
    bool internal strangerServed;
    bytes4 internal strangerRefusal;
    NameCredit.Standing internal open;
    NameCredit.Standing internal settled;

    function run() external {
        require(block.chainid == 97, "this proof runs on BNB testnet");
        uint256 key = vm.envUint("SECURITY_TESTNET_KEY");

        string memory json = vm.readFile("deployments/97.json");
        credit = NameCredit(payable(vm.parseJsonAddress(json, ".nameCredit")));
        registry = HandleRegistry(vm.parseJsonAddress(json, ".registry"));
        string memory name = string.concat("prove", vm.toString(block.number % 1_000_000_000));

        vm.startBroadcast(key);
        _act(name);
        vm.stopBroadcast();

        _report(name);
    }

    function _act(string memory name) internal {
        bytes32 pass = keccak256(abi.encode("prove", block.number));
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = keccak256(abi.encode(pass));

        borrower = new Puppet(credit);
        stranger = new Puppet(credit);
        registry.adminRegister(name, address(borrower));
        if (address(credit).balance < 0.01 ether) credit.topUp{value: 0.01 ether}();
        credit.addPasses(hashes, uint40(block.timestamp + 1 hours));

        uint256 poolBefore = address(credit).balance;
        amount = borrower.borrowWithPass(pass);
        poolWentDownBy = poolBefore - address(credit).balance;
        held = address(borrower).balance;
        open = credit.standingOf(address(borrower));

        (strangerServed, strangerRefusal) = stranger.tryBorrow();

        credit.repay{value: amount}(address(borrower));
        settled = credit.standingOf(address(borrower));
    }

    function _report(string memory name) internal view {
        console.log("chain id", block.chainid);
        console.log("NameCredit", address(credit));
        console.log("borrower name", string.concat(name, ".ai (issued by the testnet stand-in registry)"));
        console.log("borrower wallet", address(borrower));
        console.log("1. borrowed with nothing locked (with a pass, so the result does not depend on the pace), wei", amount);
        console.log("   borrower now holds, wei", held);
        console.log("   pool went down by, wei", poolWentDownBy);
        console.log("   owed, wei", open.owed);
        console.log("   due at, unix time", open.due);
        console.log("2. a wallet with no name asked too. Served:", strangerServed);
        console.log("   refused for having no Agent ID:", strangerRefusal == NameCredit.NoAgentId.selector);
        console.log("3. repaid in full. Owed now, wei", settled.owed);
        console.log("   ladder step now", settled.step);
        console.log("   next limit, wei", settled.limit);
        console.log("   next advance from, unix time", settled.notBefore);

        require(held == amount && open.owed == amount, "the advance did not arrive as recorded");
        require(poolWentDownBy == amount, "the pool did not pay exactly the advance");
        require(!strangerServed, "a wallet with no name was served");
        require(strangerRefusal == NameCredit.NoAgentId.selector, "the refusal was not for the missing name");
        require(settled.owed == 0 && settled.step == 1 && settled.limit == 2 * amount, "repayment did not move the ladder");
        console.log("PROVED: borrow with nothing locked, refusal without a name, repayment that doubles the limit.");
    }
}
