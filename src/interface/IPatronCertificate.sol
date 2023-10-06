// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @notice Kali DAO share manager interface
interface IPatronCertificate {
    function getTokenId(address target, uint256 value) external pure returns (uint256);
    function ownerOf(uint256 id) external view returns (address);

    function mint(address to, uint256 amount) external;
    function safeTransferFrom(address from, address to, uint256 id) external;
    function safeTransferFrom(address from, address to, uint256 id, bytes calldata data) external;
}
