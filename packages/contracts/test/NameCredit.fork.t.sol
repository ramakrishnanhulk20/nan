// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Runs against a fork of BNB Smart Chain mainnet, so the registry here is the real one with real holders.
// Skipped unless BSC_RPC_URL is set. Holders are taken from the registry's most recent registrations at run
// time; no name or wallet is written into this file, and none is printed.
// What this file does NOT cover: a transaction signed by a real Agentic Wallet (holders are impersonated),
// Binance's own preview and risk check, registry misbehaviour (see NameCredit.registry.t.sol), and anything
// that needs more than one term to pass.

import {Test, Vm, console} from "forge-std/Test.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {IAgentIdRegistry} from "../src/interfaces/IAgentIdRegistry.sol";

contract NameCreditForkTest is Test {
    address internal constant REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    bytes32 internal constant TRANSFER = keccak256("Transfer(address,address,uint256)");
    uint256 internal constant LOOKBACK = 20_000;

    NameCredit internal credit;
    IAgentIdRegistry internal registry = IAgentIdRegistry(REGISTRY);
    address internal owner = makeAddr("owner");
    address[] internal holders;
    bool internal forked;

    function setUp() public {
        string memory url = vm.envOr("BSC_RPC_URL", string(""));
        if (bytes(url).length == 0) return;
        vm.createSelectFork(url);
        forked = true;

        bytes32[] memory topics = new bytes32[](1);
        topics[0] = TRANSFER;
        Vm.EthGetLogs[] memory logs = vm.eth_getLogs(block.number - LOOKBACK, block.number, REGISTRY, topics);
        for (uint256 i = logs.length; i > 0 && holders.length < 5; --i) {
            address to = address(uint160(uint256(logs[i - 1].topics[2])));
            if (to.code.length == 0) holders.push(to);
        }
        require(holders.length >= 2, "need at least two recent registrations on this fork");

        NameCredit.Settings memory s =
            NameCredit.Settings({firstAdvance: 0.0003 ether, cap: 0.0048 ether, term: 3 days, pacePerDay: 100});
        credit = new NameCredit(REGISTRY, owner, s);
        vm.deal(owner, 1 ether);
        vm.prank(owner);
        credit.topUp{value: 0.1 ether}();
    }

    modifier onFork() {
        if (!forked) {
            vm.skip(true);
            return;
        }
        _;
    }

    function test_fork_registryAnswersTheThreeQuestions() public onFork {
        address holder = holders[0];
        assertEq(registry.balanceOf(holder), 1, "holder has one name");
        string memory name = registry.handleOf(holder);
        assertGt(bytes(name).length, 0, "name reads back");
        assertEq(registry.ownerOfHandle(name), holder, "name maps back to the holder");
        assertTrue(credit.holdsAgentId(holder), "contract accepts the holder");
        assertEq(credit.standingOf(holder).nameHash, bytes32(0), "nothing recorded before the first advance");
        console.log("chain id", block.chainid);
        console.log("block", block.number);
        console.log("registry code bytes", REGISTRY.code.length);
        console.log("recent holders found", holders.length);
    }

    function test_fork_realHolderBorrowsAndRepays() public onFork {
        address holder = holders[0];
        uint256 before = holder.balance;

        vm.prank(holder);
        uint256 amount = credit.borrow();
        assertEq(amount, 0.0003 ether, "first advance");
        assertEq(holder.balance, before + amount, "BNB arrived");

        NameCredit.Standing memory st = credit.standingOf(holder);
        assertEq(st.nameHash, keccak256(bytes(registry.handleOf(holder))), "name recorded");
        assertEq(st.owed, amount);
        assertEq(st.due, block.timestamp + 3 days);
        console.log("amount sent, wei", amount);

        vm.prank(holder);
        credit.repay{value: amount}(holder);
        st = credit.standingOf(holder);
        assertEq(st.owed, 0, "settled");
        assertEq(st.step, 1, "one step up");
        assertEq(st.limit, 0.0006 ether, "limit doubled");
        assertEq(st.onTime, 1);
        assertEq(holder.balance, before, "holder is back where they started");
        console.log("repaid on time, next limit wei", st.limit);
    }

    function test_fork_walletWithNoNameIsRefused() public onFork {
        address nobody = makeAddr("nobody");
        assertEq(registry.balanceOf(nobody), 0);
        assertFalse(credit.holdsAgentId(nobody));
        vm.prank(nobody);
        vm.expectRevert(NameCredit.NoAgentId.selector);
        credit.borrow();
        console.log("wallet with no name refused");
    }

    function test_fork_holdersGetOneAdvanceEachAndThePaceHolds() public onFork {
        if (holders.length < 5) {
            vm.skip(true, "fewer than five recent registrations on this fork: the pace check cannot run");
            return;
        }
        // At 100 a day, one hour of unused pace is 4 slots. A fifth caller in the same block has to wait.
        uint256 served;
        for (uint256 i; i < holders.length; ++i) {
            vm.prank(holders[i]);
            if (served == 4) {
                vm.expectRevert(abi.encodeWithSelector(NameCredit.PaceExhausted.selector, block.timestamp + 720));
                credit.borrow();
                break;
            }
            credit.borrow();
            ++served;
            vm.prank(holders[i]);
            vm.expectRevert(abi.encodeWithSelector(NameCredit.AdvanceOpen.selector, 0.0003 ether));
            credit.borrow();
        }
        assertEq(credit.totals().people, served);
        assertEq(credit.totals().outstanding, served * 0.0003 ether);
        console.log("real holders served in one block", served);

        assertEq(served, 4, "four were served and the fifth was turned away");
        skip(720);
        vm.prank(holders[4]);
        credit.borrow();
        assertEq(credit.totals().people, 5);
        console.log("fifth holder served after waiting seconds", uint256(720));
    }

    /// "Cannot come back as someone new" rests on the registry never moving or destroying a name. Its code
    /// says so (every transfer and approval reverts, and there is no burn) and its code cannot be swapped
    /// (it is not behind a proxy). This checks all of that on the live contract.
    function test_fork_aNameCanNeverMoveOrBeDestroyed() public onFork {
        address holder = holders[0];
        string memory name = registry.handleOf(holder);
        uint256 tokenId = uint256(keccak256(bytes(name)));
        address elsewhere = makeAddr("elsewhere");
        bytes4 soulbound = bytes4(keccak256("Soulbound()"));

        bytes[4] memory moves = [
            abi.encodeWithSignature("transferFrom(address,address,uint256)", holder, elsewhere, tokenId),
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", holder, elsewhere, tokenId),
            abi.encodeWithSignature("approve(address,uint256)", elsewhere, tokenId),
            abi.encodeWithSignature("setApprovalForAll(address,bool)", elsewhere, true)
        ];
        for (uint256 i; i < moves.length; ++i) {
            vm.prank(holder);
            (bool moved, bytes memory why) = REGISTRY.call(moves[i]);
            assertFalse(moved, "the holder could move or lend out the name");
            assertEq(bytes4(why), soulbound);
        }
        vm.prank(holder);
        (bool burned,) = REGISTRY.call(abi.encodeWithSignature("burn(uint256)", tokenId));
        assertFalse(burned, "the registry has no burn");

        assertEq(registry.ownerOfHandle(name), holder, "the name is where it was");
        assertEq(registry.balanceOf(elsewhere), 0);
        bytes32 implementationSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        bytes32 beaconSlot = bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1);
        assertEq(vm.load(REGISTRY, implementationSlot), bytes32(0), "the registry is not behind a proxy");
        assertEq(vm.load(REGISTRY, beaconSlot), bytes32(0), "nor behind a beacon");
        console.log("a name cannot be moved, lent out or destroyed, and the registry code cannot be swapped");
    }

    function test_fork_strangerCanRepayForAHolder() public onFork {
        address holder = holders[1];
        address friend = makeAddr("friend");
        vm.deal(friend, 1 ether);
        vm.prank(holder);
        uint256 amount = credit.borrow();
        vm.prank(friend);
        credit.repay{value: amount + 1 wei}(holder);
        assertEq(credit.standingOf(holder).owed, 0);
        assertEq(friend.balance, 1 ether - amount, "the extra wei came back");
    }
}
