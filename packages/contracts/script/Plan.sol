// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice What the mainnet deployment is meant to be: the registry it reads and the four starting settings.
///         The deploy script deploys exactly this, and the check script compares a live deployment with it.
abstract contract MainnetPlan {
    address internal constant MAINNET_REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    uint256 internal constant BSC_MAINNET = 56;

    uint96 internal constant FIRST_ADVANCE = 0.0003 ether;
    uint96 internal constant CAP = 0.0048 ether;
    uint32 internal constant TERM = 3 days;
    uint32 internal constant PACE_PER_DAY = 100;
}
