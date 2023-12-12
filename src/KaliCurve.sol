// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

import {LibString} from "solbase/utils/LibString.sol";

import {IStorage} from "./interface/IStorage.sol";
import {Storage} from "./Storage.sol";

import {KaliDAOfactory} from "./kalidao/KaliDAOfactory.sol";
import {IKaliTokenManager} from "./interface/IKaliTokenManager.sol";
import {IKaliCurve, CurveType} from "./interface/IKaliCurve.sol";

/// @notice When DAOs use math equations as basis for selling goods and services and
///         automagically form subDAOs, good things happen!
/// @author audsssy.eth
contract KaliCurve is Storage {
    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event Donated(uint256 curveId, address patron, uint256 donation, uint256 curveSupply);
    event Left(uint256 curveId, address patron, uint256 curveSupply);
    event CurveCreated(
        uint256 curveId,
        CurveType curveType,
        bool canMint,
        bool daoTreasury,
        address owner,
        uint96 scale,
        uint16 burnRatio,
        uint48 constant_a,
        uint48 constant_b,
        uint48 constant_c
    );
    event ImpactDaoSummoned(address dao);

    /// -----------------------------------------------------------------------
    /// Custom Error
    /// -----------------------------------------------------------------------

    error NotAuthorized();
    error TransferFailed();
    error NotInitialized();
    error InvalidAmount();
    error InvalidMint();
    error InvalidBurn();

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    /// @notice .
    function initialize(address dao, address daoFactory) external {
        if (daoFactory != address(0)) {
            init(dao);
            _setKaliDaoFactory(daoFactory);
        }
    }

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    modifier initialized() {
        if (this.getKaliDaoFactory() == address(0) || this.getDao() == address(0)) revert NotInitialized();
        _;
    }

    modifier onlyOwner(uint256 curveId) {
        if (this.getCurveOwner(curveId) != msg.sender) revert NotAuthorized();
        _;
    }

    modifier isOpen(uint256 curveId) {
        if (curveId == 0 || !this.getCurveMintStatus(curveId)) revert InvalidMint();
        _;
    }

    /// -----------------------------------------------------------------------
    /// Creator Logic
    /// -----------------------------------------------------------------------

    /// @notice Configure a curve.
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
    ) external payable returns (uint256 curveId) {
        // Increment and assign curveId.
        curveId = incrementCurveId();

        // Initialize curve owner.
        setCurveOwner(curveId, owner);

        // Initialize curve type.
        setCurveType(curveId, curveType);

        // Initialize curve data.
        _setCurveData(curveId, this.encodeCurveData(scale, burnRatio, constant_a, constant_b, constant_c));

        // Set mint status.
        _setCurveMintStatus(curveId, canMint);

        // Set treasury status.
        _setCurveTreasury(curveId, daoTreasury);

        // Increment curve supply to start at 1.
        incrementCurveSupply(curveId);

        emit CurveCreated(
            curveId, curveType, canMint, daoTreasury, owner, scale, burnRatio, constant_a, constant_b, constant_c
            );
    }

    /// -----------------------------------------------------------------------
    /// ImpactDAO Logic
    /// -----------------------------------------------------------------------

    /// @notice Summon ImpactDAO.
    function summonDao(uint256 curveId, address owner, address patron) private returns (address) {
        // Provide creator and patron to summon DAO.
        address[] memory voters = new address[](2);
        voters[0] = owner;
        voters[1] = patron;

        // Provide respective token amount.
        uint256[] memory tokens = new uint256[](2);
        tokens[0] = 1 ether;
        tokens[1] = 1 ether;

        // Set KaliCurve as an extension to ImpactDAO.
        address[] memory extensions = new address[](1);
        extensions[0] = address(this);
        bytes[] memory extensionsData = new bytes[](1);
        extensionsData[0] = "0x0";

        // Provide KaliDAO governance settings.
        uint32[16] memory govSettings;
        govSettings = [uint32(604800), 0, 55, 60, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];

        // Summon a KaliDAO
        uint256 count = this.getCurveCount();
        address payable impactDao = payable(
            KaliDAOfactory(this.getKaliDaoFactory()).deployKaliDAO(
                string.concat("ImpactDAO #", LibString.toString(count)),
                string.concat("ID #", LibString.toString(count)),
                " ",
                true,
                extensions,
                extensionsData,
                voters,
                tokens,
                govSettings
            )
        );

        // Store dao address for future ref.
        setImpactDao(curveId, impactDao);
        return impactDao;
    }

    /// -----------------------------------------------------------------------
    /// Claimed Logic
    /// -----------------------------------------------------------------------

    /// @notice Claim tax revenue and unsuccessful transfers.
    function claim() external payable {
        uint256 amount = this.getUnclaimed(msg.sender);
        if (amount == 0) revert NotAuthorized();

        deleteUnclaimed(msg.sender);

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /// -----------------------------------------------------------------------
    /// Patron Logic
    /// -----------------------------------------------------------------------

    /// @notice Donate to receive ImpactDAO tokens.
    function donate(uint256 curveId, address patron, uint256 donation) external payable initialized isOpen(curveId) {
        // Retrieve ImpactDAO and curve owner.
        uint256 totalDonation;
        address impactDAO = this.getImpactDao(curveId);
        address owner = this.getCurveOwner(curveId);

        // Validate mint conditions.
        if (donation != this.getPrice(true, curveId) || donation != msg.value) {
            revert InvalidAmount();
        }
        if (msg.sender == owner) revert NotAuthorized();

        // Confirm ImpactDAO exists.
        if (impactDAO == address(0)) {
            // If ImpactDAO does not exist, summon one for curve owner and patron.
            impactDAO = summonDao(curveId, owner, patron);

            // Lock amount of burn price in contract to cover future burns.
            totalDonation = donation - this.getPrice(false, curveId);
        } else {
            // Confirm new or recurring patron.
            if (IKaliTokenManager(impactDAO).balanceOf(patron) > 0) {
                // Recurring patrons contribute entire donations.
                totalDonation = donation;
            } else {
                // New patrons receive one ether amount of ImpactDAO tokens.
                IKaliTokenManager(impactDAO).mintTokens(owner, 1 ether);
                IKaliTokenManager(impactDAO).mintTokens(patron, 1 ether);

                // Lock token amount in burn price to cover future burns.
                totalDonation = donation - this.getPrice(false, curveId);
            }
        }

        // Distribute donation.
        addUnclaimed(this.getCurveTreasury(curveId) ? impactDAO : owner, totalDonation);

        emit Donated(curveId, patron, donation, incrementCurveSupply(curveId));
    }

    /// @notice Burn ImpactDAO tokens.
    function leave(uint256 curveId, address patron) external payable initialized {
        // Retrieve ImpactDAO and check if patron is eligible to leave.
        address impactDAO = this.getImpactDao(curveId);
        if (IKaliTokenManager(impactDAO).balanceOf(patron) == 0) revert InvalidBurn();

        // Add burn price to patron's unclaimed.
        addUnclaimed(patron, this.getPrice(false, curveId));

        // Burn ImpactDAO tokens.
        IKaliTokenManager(impactDAO).burnTokens(this.getCurveOwner(curveId), 1 ether);
        IKaliTokenManager(impactDAO).burnTokens(patron, 1 ether);

        // Decrement supply.
        // uint256 supply = ;

        emit Left(curveId, patron, decrementCurveSupply(curveId));
    }

    /// -----------------------------------------------------------------------
    /// Operator Setter Logic
    /// -----------------------------------------------------------------------

    /// @notice .
    function setKaliDaoFactory(address factory) external payable initialized onlyOperator {
        _setKaliDaoFactory(factory);
    }

    /// @notice .
    function _setKaliDaoFactory(address factory) internal {
        _setAddress(keccak256(abi.encode("dao.factory")), factory);
    }

    /// -----------------------------------------------------------------------
    /// Curve Setter Logic
    /// -----------------------------------------------------------------------

    /// @notice .
    function setCurveMintStatus(uint256 curveId, bool canMint) external payable onlyOwner(curveId) {
        _setCurveMintStatus(curveId, canMint);
    }

    /// @notice .
    function setCurveTreasury(uint256 curveId, bool daoTreasury) external payable onlyOwner(curveId) {
        _setCurveTreasury(curveId, daoTreasury);
    }

    /// @notice .
    function setCurveData(uint256 curveId, uint256 key) external payable onlyOwner(curveId) {
        _setCurveData(curveId, key);
    }

    /// @notice .
    function setCurveOwner(uint256 curveId, address owner) internal {
        if (owner == address(0)) revert NotAuthorized();
        _setAddress(keccak256(abi.encode(curveId, ".owner")), owner);
    }

    /// @notice .
    function setCurveType(uint256 curveId, CurveType curveType) internal {
        _setUint(keccak256(abi.encode(curveId, ".curveType")), uint256(curveType));
    }

    /// @notice .
    function _setCurveData(uint256 curveId, uint256 key) internal {
        _setUint(keccak256(abi.encode(curveId, ".data")), key);
    }

    /// @notice .
    function _setCurveMintStatus(uint256 curveId, bool canMint) internal {
        if (canMint != this.getCurveMintStatus(curveId)) _setBool(keccak256(abi.encode(curveId, ".canMint")), canMint);
    }

    /// @notice .
    function _setCurveTreasury(uint256 curveId, bool daoTreasury) internal {
        if (daoTreasury != this.getCurveTreasury(curveId)) {
            _setBool(keccak256(abi.encode(curveId, ".daoTreasury")), daoTreasury);
        }
    }

    /// @notice .
    function setImpactDao(uint256 curveId, address impactDao) internal {
        _setAddress(keccak256(abi.encode(curveId, ".impactDao")), impactDao);

        emit ImpactDaoSummoned(impactDao);
    }

    /// -----------------------------------------------------------------------
    /// Operator Getter Logic
    /// -----------------------------------------------------------------------

    /// @notice .
    function getKaliDaoFactory() external view returns (address) {
        return this.getAddress(keccak256(abi.encode("dao.factory")));
    }

    /// @notice .
    function getCurveCount() external view returns (uint256) {
        return this.getUint(keccak256(abi.encode("curves.count")));
    }

    /// -----------------------------------------------------------------------
    /// Curve Getter Logic
    /// -----------------------------------------------------------------------

    /// @notice Return owner of a curve.
    function getCurveOwner(uint256 curveId) external view returns (address) {
        return this.getAddress(keccak256(abi.encode(curveId, ".owner")));
    }

    /// @notice Return current supply of a curve.
    function getCurveSupply(uint256 curveId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(curveId, ".supply")));
    }

    /// @notice Return mint status of a curve.
    function getCurveMintStatus(uint256 curveId) external view returns (bool) {
        return this.getBool(keccak256(abi.encode(curveId, ".canMint")));
    }

    /// @notice Return wheter of a curve uses user or DAO treasury.
    function getCurveTreasury(uint256 curveId) external view returns (bool) {
        return this.getBool(keccak256(abi.encode(curveId, ".daoTreasury")));
    }

    /// @notice Return type of a curve.
    function getCurveType(uint256 curveId) external view returns (CurveType) {
        return CurveType(this.getUint(keccak256(abi.encode(curveId, ".curveType"))));
    }

    /// @notice Return curve data in order - scale, burnRatio, constant_a, constant_b, constant_c.
    function getCurveData(uint256 curveId) external view returns (uint256, uint256, uint256, uint256, uint256) {
        return this.decodeCurveData(this.getUint(keccak256(abi.encode(curveId, ".data"))));
    }

    // mint formula - initMintPrice + supply * initMintPrice / 50 + (supply ** 2) * initMintPrice / 100;
    // burn formula - initMintPrice + supply * initMintPrice / 50 + (supply ** 2) * initMintPrice / 200;

    /// @notice Calculate mint and burn price.
    function getPrice(bool mint, uint256 curveId) external view virtual returns (uint256) {
        // Retrieve curve data.
        CurveType curveType = this.getCurveType(curveId);
        uint256 supply = this.getCurveSupply(curveId);
        (uint256 scale, uint256 burnRatio, uint256 constant_a, uint256 constant_b, uint256 constant_c) =
            this.getCurveData(curveId);

        // Update curve data based on request for mint or burn price.
        supply = mint ? supply + 1 : supply;
        burnRatio = mint ? 100 : uint256(100) - burnRatio;

        if (curveType == CurveType.LINEAR) {
            // Return linear pricing based on, a * b * x + b.
            return (constant_a * supply * scale + constant_b * scale) * burnRatio / 100;
        } else if (curveType == CurveType.POLY) {
            // Return curve pricing based on, a * c * x^2 + b * c * x + c.
            return (constant_a * (supply ** 2) * scale + constant_b * supply * scale + constant_c * scale) * burnRatio
                / 100;
        } else {
            return 0;
        }
    }

    /// @notice Return mint and burn price difference of a curve.
    function getMintBurnDifference(uint256 curveId) external view returns (uint256) {
        return this.getPrice(true, curveId) - this.getPrice(false, curveId);
    }

    /// @notice Return unclaimed amount by a user.
    function getUnclaimed(address user) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(user, ".unclaimed")));
    }

    /// @notice Return ImpactDAO of curve.
    function getImpactDao(uint256 curveId) external view returns (address) {
        return this.getAddress(keccak256(abi.encode(curveId, ".impactDao")));
    }

    /// -----------------------------------------------------------------------
    /// Counter Logic
    /// -----------------------------------------------------------------------

    /// @notice Internal function to increment number of total curves.
    function incrementCurveId() internal returns (uint256) {
        return addUint(keccak256(abi.encode("curves.count")), 1);
    }

    /// @notice Internal function to add to unclaimed amount.
    function addUnclaimed(address user, uint256 amount) internal {
        addUint(keccak256(abi.encode(user, ".unclaimed")), amount);
    }

    /// @notice Internal function to increment supply of a curve.
    function incrementCurveSupply(uint256 curveId) internal returns (uint256) {
        return addUint(keccak256(abi.encode(curveId, ".supply")), 1);
    }

    /// @notice Internal function to decrement supply of a curve.
    function decrementCurveSupply(uint256 curveId) internal returns (uint256) {
        return subUint(keccak256(abi.encode(curveId, ".supply")), 1);
    }

    /// -----------------------------------------------------------------------
    /// Delete Logic
    /// -----------------------------------------------------------------------

    /// @notice Internal function to delete unclaimed amount.
    function deleteUnclaimed(address user) internal {
        deleteUint(keccak256(abi.encode(user, ".unclaimed")));
    }

    /// -----------------------------------------------------------------------
    /// Helper Logic
    /// -----------------------------------------------------------------------

    function encodeCurveData(uint96 scale, uint16 burnRatio, uint48 constant_a, uint48 constant_b, uint48 constant_c)
        external
        pure
        returns (uint256)
    {
        return uint256(bytes32(abi.encodePacked(scale, burnRatio, constant_a, constant_b, constant_c)));
    }

    function decodeCurveData(uint256 key) external pure returns (uint256, uint256, uint256, uint256, uint256) {
        // Convert tokenId from type uint256 to bytes32.
        bytes32 _key = bytes32(key);

        // Declare variables to return later.
        uint48 constant_c;
        uint48 constant_b;
        uint48 constant_a;
        uint16 burnRatio;
        uint96 scale;

        // Parse data via assembly.
        assembly {
            constant_c := _key // 0-47
            constant_b := shr(48, _key) // 48-95
            constant_a := shr(96, _key) // 96-143
            burnRatio := shr(144, _key) // 144-147
            scale := shr(160, _key) // 160-
        }

        return (uint256(scale), uint256(burnRatio), uint256(constant_a), uint256(constant_b), uint256(constant_c));
    }

    receive() external payable virtual {}
}
