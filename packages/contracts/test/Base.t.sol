// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {NameCredit} from "../src/NameCredit.sol";
import {HandleRegistry} from "./mocks/HandleRegistry.sol";

/// @dev Shared setup: the registry's own source deployed locally, three named wallets, one wallet with no
///      name, and a funded pool with the starting settings.
abstract contract Base is Test {
    uint96 internal constant FIRST = 0.0003 ether;
    uint96 internal constant CAP = 0.0048 ether;
    uint32 internal constant TERM = 3 days;
    uint32 internal constant PACE = 100;
    uint256 internal constant START = 1_795_000_000;
    uint256 internal constant GRACE = 1 days;
    uint256 internal constant COOLING_OFF = 7 days;

    HandleRegistry internal registry;
    NameCredit internal credit;
    address internal owner = makeAddr("owner");
    address internal registryOwner = makeAddr("registryOwner");
    address internal nobody = makeAddr("nobody");
    address internal alice;
    address internal bob;
    address internal carol;

    function setUp() public virtual {
        vm.warp(START);
        vm.prank(registryOwner);
        registry = new HandleRegistry(makeAddr("signer"), 3, 15, "", "");
        alice = _holder("alice");
        bob = _holder("bob");
        carol = _holder("carol");
        credit = new NameCredit(address(registry), owner, _defaults());
        vm.deal(owner, 100 ether);
        vm.prank(owner);
        credit.topUp{value: 1 ether}();
        vm.deal(nobody, 1 ether);
    }

    function _defaults() internal pure returns (NameCredit.Settings memory) {
        return NameCredit.Settings({firstAdvance: FIRST, cap: CAP, term: TERM, pacePerDay: PACE});
    }

    function _name(string memory name, address who) internal {
        vm.prank(registryOwner);
        registry.adminRegister(name, who);
    }

    function _holder(string memory name) internal returns (address who) {
        who = makeAddr(name);
        _name(name, who);
        vm.deal(who, 1 ether);
    }

    function _borrow(address who) internal returns (uint256 amount) {
        vm.prank(who);
        amount = credit.borrow();
    }

    function _repay(address who) internal {
        uint256 owed = credit.standingOf(who).owed;
        vm.prank(who);
        credit.repay{value: owed}(who);
    }

    function _st(address who) internal view returns (NameCredit.Standing memory) {
        return credit.standingOf(who);
    }
}
