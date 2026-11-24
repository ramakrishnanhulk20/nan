// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// TEST ONLY. Registries and wallets that misbehave on purpose.

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {NameCredit} from "../../src/NameCredit.sol";

/// @dev Answers each registry read with whatever raw bytes the test sets, or reverts, or spins until it
///      runs out of gas, or sends back the set bytes followed by a flood of extra data.
contract RawRegistry {
    struct Answer {
        uint8 mode; // 0 return data, 1 revert with data, 2 spin, 3 return data then zeros up to FLOOD bytes
        bytes data;
    }

    /// @dev 100,000 bytes cost about 29,000 gas of memory, so the flood fits inside the 60,000 gas the caller
    ///      allows a read. A megabyte would run out of gas inside the registry and never reach the caller.
    uint256 public constant FLOOD = 100_000;

    mapping(bytes4 => Answer) private _answers;

    function set(bytes4 selector, uint8 mode, bytes calldata data) external {
        _answers[selector] = Answer(mode, data);
    }

    fallback() external {
        Answer storage a = _answers[msg.sig];
        uint8 mode = a.mode;
        if (mode == 2) {
            uint256 i;
            while (true) {
                unchecked {
                    ++i;
                }
            }
        }
        bytes memory d = a.data;
        if (mode == 1) {
            assembly {
                revert(add(d, 32), mload(d))
            }
        }
        if (mode == 3) {
            // The reply opens with the set bytes, which the test makes a well-formed answer. Only a check on
            // the reply's size can then refuse it.
            uint256 size = FLOOD;
            assembly {
                return(add(d, 32), size)
            }
        }
        assembly {
            return(add(d, 32), mload(d))
        }
    }
}

/// @dev Refuses any BNB sent to it, whether it is borrowing, paying for someone or owning the pool.
contract RejectingWallet {
    NameCredit private immutable CREDIT;

    constructor(NameCredit credit) {
        CREDIT = credit;
    }

    function borrow() external {
        CREDIT.borrow();
    }

    function repayFor(address borrower) external payable {
        CREDIT.repay{value: msg.value}(borrower);
    }

    function acceptOwnership() external {
        CREDIT.acceptOwnership();
    }

    function withdraw(uint256 amount) external {
        CREDIT.withdraw(amount);
    }

    receive() external payable {
        revert("no thanks");
    }
}

/// @dev On receiving BNB, calls back into the credit contract in the way the test chose. It keeps the BNB
///      and swallows the inner failure, so the outer call completes and the test can read exactly why the
///      call back was refused and what the books said at that moment.
contract ReenteringWallet {
    NameCredit private immutable CREDIT;
    uint8 public mode; // 1 borrow again, 2 repay own advance, 3 mark the watched wallet missed, 4 withdraw
    address public watch;
    bool public calledBack;
    bool public callBackWentThrough;
    bytes4 public innerReason;
    uint256 public owedSeen;
    uint256 public outstandingSeen;

    constructor(NameCredit credit) {
        CREDIT = credit;
        watch = address(this);
    }

    function setMode(uint8 newMode) external {
        mode = newMode;
    }

    function setWatch(address who) external {
        watch = who;
    }

    function borrow() external returns (uint256) {
        return CREDIT.borrow();
    }

    function repayFor(address borrower) external payable {
        CREDIT.repay{value: msg.value}(borrower);
    }

    receive() external payable {
        owedSeen = CREDIT.standingOf(watch).owed;
        outstandingSeen = CREDIT.totals().outstanding;

        bytes memory data;
        uint256 value;
        if (mode == 1) {
            data = abi.encodeCall(NameCredit.borrow, ());
        } else if (mode == 2) {
            data = abi.encodeCall(NameCredit.repay, (address(this)));
            value = msg.value;
        } else if (mode == 3) {
            data = abi.encodeCall(NameCredit.markMissed, (watch));
        } else if (mode == 4) {
            data = abi.encodeCall(NameCredit.withdraw, (1));
        } else {
            return;
        }
        (bool ok, bytes memory ret) = address(CREDIT).call{value: value}(data);
        calledBack = true;
        callBackWentThrough = ok;
        innerReason = ret.length >= 4 ? bytes4(ret) : bytes4(0);
    }
}

/// @dev Spins forever when sent BNB.
contract GasBurningWallet {
    NameCredit private immutable CREDIT;

    constructor(NameCredit credit) {
        CREDIT = credit;
    }

    function borrow() external {
        CREDIT.borrow();
    }

    receive() external payable {
        uint256 i;
        while (true) {
            unchecked {
                ++i;
            }
        }
    }
}

contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1_000_000 ether);
    }
}
