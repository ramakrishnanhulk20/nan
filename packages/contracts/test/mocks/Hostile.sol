// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// TEST ONLY. Registries and wallets that misbehave on purpose.

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {NameCredit} from "../../src/NameCredit.sol";

/// @dev Answers each registry read with whatever raw bytes the test sets, or reverts, or spins until it
///      runs out of gas, or sends back far more data than asked for.
contract RawRegistry {
    struct Answer {
        uint8 mode; // 0 return data, 1 revert with data, 2 spin, 3 return a megabyte
        bytes data;
    }

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
        if (mode == 3) {
            assembly {
                return(0, 0x100000)
            }
        }
        bytes memory d = a.data;
        if (mode == 1) {
            assembly {
                revert(add(d, 32), mload(d))
            }
        }
        assembly {
            return(add(d, 32), mload(d))
        }
    }
}

/// @dev Refuses any BNB sent to it.
contract RejectingWallet {
    NameCredit private immutable CREDIT;

    constructor(NameCredit credit) {
        CREDIT = credit;
    }

    function borrow() external {
        CREDIT.borrow();
    }

    receive() external payable {
        revert("no thanks");
    }
}

/// @dev On receiving BNB, calls back into the credit contract in the way the test chose.
contract ReenteringWallet {
    NameCredit private immutable CREDIT;
    uint8 public mode; // 1 borrow again, 2 repay own advance, 3 mark self missed, 4 withdraw
    bytes public lastRevert;

    constructor(NameCredit credit) {
        CREDIT = credit;
    }

    function setMode(uint8 newMode) external {
        mode = newMode;
    }

    function borrow() external returns (uint256) {
        return CREDIT.borrow();
    }

    function repayFor(address borrower) external payable {
        CREDIT.repay{value: msg.value}(borrower);
    }

    receive() external payable {
        if (mode == 1) CREDIT.borrow();
        if (mode == 2) CREDIT.repay{value: msg.value}(address(this));
        if (mode == 3) CREDIT.markMissed(address(this));
        if (mode == 4) CREDIT.withdraw(1);
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
