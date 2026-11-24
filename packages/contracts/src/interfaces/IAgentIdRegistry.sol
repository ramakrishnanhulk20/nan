// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title The three reads this project makes on the Agent ID registry
/// @notice The registry is SPACE ID's `HandleRegistry` on BNB Smart Chain. One wallet holds at most one name,
///         one name has exactly one wallet, and neither can ever change.
interface IAgentIdRegistry {
    /// @notice How many Agent IDs a wallet holds: one or none.
    /// @param owner The wallet to check.
    /// @return Greater than zero when `owner` holds an Agent ID.
    function balanceOf(address owner) external view returns (uint256);

    /// @notice The name a wallet holds.
    /// @param owner The wallet to check.
    /// @return The name without the `.ai` ending. Empty when the wallet holds none.
    function handleOf(address owner) external view returns (string memory);

    /// @notice The wallet that holds a name.
    /// @param handle The name without the `.ai` ending.
    /// @return The holder. The zero address when nobody holds the name.
    function ownerOfHandle(string calldata handle) external view returns (address);
}
