// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

enum CurveType {
    NA,
    LINEAR,
    POLY
}

/// @notice Kali DAO share manager interface
interface IKaliCurve {
    /// @dev DAO logic
    function setKaliDaoFactory(address factory) external payable;
    function getKaliDaoFactory() external view returns (address);

    /// @dev User logic.
    function donate(uint256 curveId, address patron, uint256 donation) external payable;
    function leave(uint256 curveId, address patron) external payable;
    function claim() external payable;

    /// @dev Creator logic
    function curve(
        CurveType curveType,
        bool canMint,
        bool daoTreasury,
        address owner,
        uint96 scale,
        uint16 burnRatio, // Relative to mint price.
        uint48 constant_a,
        uint48 constant_b,
        uint48 constant_c
    ) external payable returns (uint256 curveId);

    /// @dev Curve setter logic
    function setCurveDetail(uint256 curveId, string calldata detail) external payable;
    function setCurveMintStatus(uint256 curveId, bool canMint) external payable;
    function setCurveTreasury(uint256 curveId, bool daoTreasury) external payable;
    function setCurveData(uint256 curveId, uint256 key) external payable;

    /// @dev Curve getter logic.
    function getCurveOwner(uint256 curveId) external view returns (address);
    function getCurveSupply(uint256 curveId) external view returns (uint256);
    function getCurveMintStatus(uint256 curveId) external view returns (bool);
    function getCurveTreasury(uint256 curveId) external view returns (bool);
    function getCurveType(uint256 curveId) external view returns (CurveType);
    function getCurveData(uint256 curveId) external view returns (uint256, uint256, uint256, uint256, uint256);
    function getPrice(bool mint, uint256 curveId) external view returns (uint256);
    function getMintBurnDifference(uint256 curveId) external view returns (uint256);
    function getUnclaimed(address user) external view returns (uint256);
    function getImpactDao(uint256 curveId) external view returns (address);

    /// @dev Helper Logic
    function encodeCurveData(uint96 scale, uint16 burnRatio, uint48 constant_a, uint48 constant_b, uint48 constant_c)
        external
        pure
        returns (uint256);
    function decodeCurveData(uint256 key) external pure returns (uint256, uint256, uint256, uint256, uint256);
}
