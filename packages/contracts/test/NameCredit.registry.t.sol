// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Threat model rules C1, C2 and C11: what happens when the registry lies, breaks, stalls or floods.
// The registry here is a stand-in that returns whatever raw bytes the test sets.
// What this file does NOT cover: the real registry's behaviour (NameCredit.fork.t.sol), and a registry whose
// owner issues real names to an attacker, which this contract cannot tell from an honest registration.

import {NameCredit} from "../src/NameCredit.sol";
import {IAgentIdRegistry} from "../src/interfaces/IAgentIdRegistry.sol";
import {Base} from "./Base.t.sol";
import {RawRegistry} from "./mocks/Hostile.sol";

contract NameCreditRegistryTest is Base {
    bytes4 internal constant BALANCE = IAgentIdRegistry.balanceOf.selector;
    bytes4 internal constant HANDLE = IAgentIdRegistry.handleOf.selector;
    bytes4 internal constant OWNER_OF = IAgentIdRegistry.ownerOfHandle.selector;

    // Measured with the ceilings in place: 68,895, 72,386 and 85,611 gas for a stall in the first, second
    // and third read, and 46,636 to 70,035 for a flood. The bounds sit a little above. Copying the flood
    // back would add about 38,000, and a stall with no ceiling would take nearly all the gas sent.
    uint256 internal constant SPIN_BOUND_FIRST = 75_000;
    uint256 internal constant SPIN_BOUND_SECOND = 80_000;
    uint256 internal constant SPIN_BOUND_THIRD = 95_000;
    uint256 internal constant FLOOD_BOUND = 80_000;

    RawRegistry internal raw;
    NameCredit internal rawCredit;
    address internal mallory = makeAddr("mallory");

    function setUp() public override {
        super.setUp();
        raw = new RawRegistry();
        rawCredit = new NameCredit(address(raw), owner, _defaults());
        vm.prank(owner);
        rawCredit.topUp{value: 1 ether}();
        vm.deal(mallory, 1 ether);
        _honest("mallory", mallory);
    }

    function _honest(string memory name, address who) internal {
        raw.set(BALANCE, 0, abi.encode(uint256(1)));
        raw.set(HANDLE, 0, abi.encode(name));
        raw.set(OWNER_OF, 0, abi.encode(who));
    }

    function _assertRefused(string memory why) internal {
        assertFalse(rawCredit.holdsAgentId(mallory), why);
        (NameCredit.Refusal r,,) = rawCredit.quoteBorrow(mallory);
        assertEq(uint8(r), uint8(NameCredit.Refusal.NoAgentId), why);
        vm.prank(mallory);
        vm.expectRevert(NameCredit.NoAgentId.selector);
        rawCredit.borrow{gas: 600_000}();
        assertEq(rawCredit.totals().people, 0, why);
        assertEq(address(rawCredit).balance, 1 ether, why);
    }

    function test_honestAnswersGetAnAdvance() public {
        assertTrue(rawCredit.holdsAgentId(mallory));
        vm.prank(mallory);
        assertEq(rawCredit.borrow(), FIRST);
        assertEq(rawCredit.standingOf(mallory).nameHash, keccak256("mallory"));
    }

    function test_balance_revertZeroOrWrongSizeIsRefused() public {
        raw.set(BALANCE, 1, "");
        _assertRefused("balanceOf reverts");
        raw.set(BALANCE, 0, abi.encode(uint256(0)));
        _assertRefused("balanceOf says zero");
        raw.set(BALANCE, 0, hex"01");
        _assertRefused("balanceOf answers one byte");
        raw.set(BALANCE, 0, "");
        _assertRefused("balanceOf answers nothing");
        raw.set(BALANCE, 0, abi.encode(uint256(1), uint256(1)));
        _assertRefused("balanceOf answers two words");
    }

    /// A read that never answers costs the caller its 60,000 gas ceiling and little more, whichever of the
    /// three reads it is. With no ceiling it would take 63/64 of everything the caller sent.
    function test_aStalledReadCostsTheCallerABoundedAmount() public {
        bytes4[3] memory reads = [BALANCE, HANDLE, OWNER_OF];
        uint256[3] memory bounds = [uint256(SPIN_BOUND_FIRST), SPIN_BOUND_SECOND, SPIN_BOUND_THIRD];
        for (uint256 i; i < 3; ++i) {
            _honest("mallory", mallory);
            raw.set(reads[i], 2, "");
            uint256 gasBefore = gasleft();
            assertFalse(rawCredit.holdsAgentId(mallory));
            uint256 used = gasBefore - gasleft();
            emit log_named_uint("gas for a check with one stalled read", used);
            assertLt(used, bounds[i], "one stalled read costs its ceiling and little more");
            _assertRefused("a read spins");
        }
    }

    /// The flood opens with a well-formed answer, so nothing but the size ceiling can refuse it, and the
    /// caller must not pay to copy it. The name is 40 bytes so that its honest answer fills all 128 bytes
    /// the contract is willing to read.
    function test_aFloodOfReturnDataIsRefusedOnEveryRead() public {
        string memory name = "a40bytenameaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        assertEq(bytes(name).length, 40);
        bytes4[3] memory reads = [BALANCE, HANDLE, OWNER_OF];
        bytes[3] memory wellFormed = [abi.encode(uint256(1)), abi.encode(name), abi.encode(mallory)];
        for (uint256 i; i < 3; ++i) {
            _honest(name, mallory);
            assertTrue(rawCredit.holdsAgentId(mallory), "the honest answers are accepted");
            raw.set(reads[i], 3, wellFormed[i]);

            (bool ok, bytes memory flood) = address(raw).staticcall{gas: 60_000}(abi.encodeWithSelector(reads[i], mallory));
            assertTrue(ok, "the flood fits inside the gas the contract allows a read");
            assertEq(flood.length, raw.FLOOD(), "and it really is a flood");

            uint256 gasBefore = gasleft();
            assertFalse(rawCredit.holdsAgentId(mallory));
            uint256 used = gasBefore - gasleft();
            emit log_named_uint("gas for a check with one flooded read", used);
            assertLt(used, FLOOD_BOUND, "the caller did not pay to copy the flood");
            _assertRefused("a read floods");
        }
    }

    function test_handle_revertEmptyOrMalformedIsRefused() public {
        raw.set(HANDLE, 1, "");
        _assertRefused("handleOf reverts");
        raw.set(HANDLE, 0, abi.encode(""));
        _assertRefused("empty name");
        raw.set(HANDLE, 0, "");
        _assertRefused("no data");
        raw.set(HANDLE, 0, abi.encode(uint256(1)));
        _assertRefused("one word");
        raw.set(HANDLE, 0, abi.encode(uint256(64), uint256(7), bytes32("mallory")));
        _assertRefused("offset is not 32");
        raw.set(HANDLE, 0, abi.encode(uint256(32), uint256(40), bytes32("mallory")));
        _assertRefused("length runs past the data");
        raw.set(HANDLE, 0, abi.encode(uint256(32), uint256(7), bytes32("mallory"), bytes32(0)));
        _assertRefused("more words than the length needs");
        raw.set(HANDLE, 0, abi.encode(uint256(32), type(uint256).max, bytes32("mallory")));
        _assertRefused("absurd length");
    }

    function test_handle_aNameLongerThan64BytesIsRefused() public {
        bytes memory long = new bytes(65);
        for (uint256 i; i < 65; ++i) {
            long[i] = "a";
        }
        raw.set(HANDLE, 0, abi.encode(string(long)));
        _assertRefused("65 byte name");
    }

    function test_ownerOf_revertMismatchOrDirtyIsRefused() public {
        raw.set(OWNER_OF, 1, "");
        _assertRefused("ownerOfHandle reverts");
        raw.set(OWNER_OF, 0, abi.encode(alice));
        _assertRefused("the name belongs to someone else");
        raw.set(OWNER_OF, 0, abi.encode(address(0)));
        _assertRefused("the name belongs to nobody");
        raw.set(OWNER_OF, 0, abi.encode(uint256(uint160(mallory)) | (uint256(1) << 200)));
        _assertRefused("address with stray high bits");
        raw.set(OWNER_OF, 0, abi.encode(mallory, mallory));
        _assertRefused("two words");
    }

    function test_aNameThatChangesIsRefused() public {
        vm.prank(mallory);
        rawCredit.borrow();
        vm.prank(mallory);
        rawCredit.repay{value: FIRST}(mallory);
        skip(TERM);
        _honest("someoneelse", mallory);
        vm.prank(mallory);
        vm.expectRevert(NameCredit.NameMismatch.selector);
        rawCredit.borrow();
        (NameCredit.Refusal r,,) = rawCredit.quoteBorrow(mallory);
        assertEq(uint8(r), uint8(NameCredit.Refusal.NoAgentId));
    }

    function test_aDeadRegistryCannotBlockRepaymentOrMarking() public {
        vm.prank(mallory);
        rawCredit.borrow();
        raw.set(BALANCE, 2, "");
        raw.set(HANDLE, 2, "");
        raw.set(OWNER_OF, 2, "");

        assertEq(rawCredit.standingOf(mallory).owed, FIRST);
        skip(TERM + GRACE + 1);
        rawCredit.markMissed(mallory);
        assertTrue(rawCredit.standingOf(mallory).missed);
        vm.prank(nobody);
        rawCredit.repay{value: FIRST}(mallory);
        assertEq(rawCredit.standingOf(mallory).owed, 0);
        assertEq(rawCredit.standingOf(mallory).late, 1);
    }

    /// The name on file is not enough. A borrower who was served before is asked about again, every time.
    function test_aReturningBorrowerIsRefusedOnceTheRegistryStopsAnswering() public {
        _borrow(alice);
        _repay(alice);
        vm.warp(START + TERM);
        vm.etch(address(registry), hex"fe");
        (NameCredit.Refusal r,,) = credit.quoteBorrow(alice);
        assertEq(uint8(r), uint8(NameCredit.Refusal.NoAgentId));
        vm.prank(alice);
        vm.expectRevert(NameCredit.NoAgentId.selector);
        credit.borrow();
        assertEq(_st(alice).owed, 0);
    }

    function test_theRealRegistryReplacedByBrokenCodeCannotBlockRepayment() public {
        _borrow(alice);
        _borrow(bob);
        vm.etch(address(registry), hex"fe");
        assertFalse(credit.holdsAgentId(carol));
        vm.prank(carol);
        vm.expectRevert(NameCredit.NoAgentId.selector);
        credit.borrow();

        _repay(alice);
        assertEq(_st(alice).owed, 0);
        skip(TERM + GRACE + 1);
        credit.markMissed(bob);
        assertTrue(_st(bob).missed);
        vm.prank(nobody);
        credit.repay{value: FIRST}(bob);
        assertEq(_st(bob).owed, 0);
    }

    function test_namesOfEveryWordBoundaryLengthWork() public {
        vm.prank(registryOwner);
        registry.setLengthBounds(1, 64);
        uint8[7] memory lengths = [1, 3, 31, 32, 33, 63, 64];
        vm.prank(owner);
        credit.scheduleSettings(NameCredit.Settings({firstAdvance: FIRST, cap: CAP, term: TERM, pacePerDay: 10_000}));
        skip(12 hours);
        credit.applySettings();
        skip(1 hours);
        for (uint256 i; i < lengths.length; ++i) {
            bytes memory name = new bytes(lengths[i]);
            for (uint256 j; j < lengths[i]; ++j) {
                name[j] = bytes1(uint8(97 + (i % 26)));
            }
            address who = makeAddr(string(abi.encodePacked("len", lengths[i])));
            _name(string(name), who);
            vm.prank(who);
            assertEq(credit.borrow(), FIRST);
            assertEq(_st(who).nameHash, keccak256(name));
        }
    }

    /// An advance is made exactly when the registry's name answer is the canonical encoding of a string of
    /// 1 to 64 bytes. Anything else is refused.
    function testFuzz_onlyACanonicalNameAnswerIsAccepted(bytes calldata answer) public {
        vm.assume(answer.length <= 256);
        raw.set(HANDLE, 0, answer);

        bool canonical = false;
        if (answer.length == 96 || answer.length == 128) {
            (uint256 offset, uint256 length) = abi.decode(answer, (uint256, uint256));
            canonical = offset == 32 && length >= 1 && length <= 64 && answer.length == 64 + ((length + 31) / 32) * 32;
        }
        assertEq(rawCredit.holdsAgentId(mallory), canonical);
        vm.prank(mallory);
        if (!canonical) vm.expectRevert(NameCredit.NoAgentId.selector);
        rawCredit.borrow();
    }

    /// The same rule with answers built from parts, so that the accepting side is reached about one run in
    /// ten. Random bytes almost never form an acceptable answer.
    function testFuzz_nameAnswersBuiltFromParts(bool rightOffset, uint8 length, uint8 words) public {
        length = uint8(bound(length, 0, 70));
        words = uint8(bound(words, 0, 3));
        bytes memory answer = abi.encodePacked(uint256(rightOffset ? 32 : 64), uint256(length));
        for (uint256 i; i < words; ++i) {
            answer = bytes.concat(answer, bytes32("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
        }
        raw.set(HANDLE, 0, answer);

        bool canonical = rightOffset && length >= 1 && length <= 64 && words == (uint256(length) + 31) / 32;
        assertEq(rawCredit.holdsAgentId(mallory), canonical);
        vm.prank(mallory);
        if (!canonical) vm.expectRevert(NameCredit.NoAgentId.selector);
        rawCredit.borrow();
    }

    function testFuzz_anyOwnerAnswerButTheCallerIsRefused(uint256 answer) public {
        vm.assume(answer != uint256(uint160(mallory)));
        raw.set(OWNER_OF, 0, abi.encode(answer));
        assertFalse(rawCredit.holdsAgentId(mallory));
    }

    function testFuzz_wellFormedNamesRoundTrip(uint8 length, uint8 fill) public {
        length = uint8(bound(length, 1, 64));
        bytes memory name = new bytes(length);
        for (uint256 i; i < length; ++i) {
            name[i] = bytes1(fill);
        }
        _honest(string(name), mallory);
        vm.prank(mallory);
        rawCredit.borrow();
        assertEq(rawCredit.standingOf(mallory).nameHash, keccak256(name));
    }
}
