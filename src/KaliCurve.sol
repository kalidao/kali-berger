// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

import {LibString} from "solbase/utils/LibString.sol";
import {IERC721} from "forge-std/interfaces/IERC721.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

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
    /// Custom Error
    /// -----------------------------------------------------------------------

    error NotAuthorized();
    error TransferFailed();
    error NotInitialized();
    error InvalidCurveParam();
    error InvalidAmount();
    error InvalidMint();
    error InvalidBurn();

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

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

    modifier forSale(uint256 curveId) {
        if (!this.getCurveMintStatus(curveId)) revert NotAuthorized();
        _;
    }

    /// -----------------------------------------------------------------------
    /// Creator Logic
    /// -----------------------------------------------------------------------

    /// @notice Configure a curve.
    function curve(
        uint256 curveId,
        address owner,
        CurveType curveType,
        uint256 scale,
        uint256 burnRatio, // Relative to mint price.
        uint256 constant_a,
        uint256 constant_b,
        uint256 constant_c,
        bool canMint,
        bool daoTreasury
    ) external payable returns (uint256) {
        // Setup new curve.
        if (curveId == 0) {
            // Increment and assign curveId.
            curveId = incrementCurveId();

            // Initialize curve owner.
            setCurveOwner(curveId, owner);

            // Initialize curve type.
            setCurveType(curveId, curveType);

            // Initialize curve scale.
            setCurveScale(curveId, scale);

            // Initialize curve scale.
            setCurveBurnRatio(curveId, burnRatio);

            // Initialize curve constant.
            _setMintConstantA(curveId, constant_a);

            // Initialize curve constant.
            _setMintConstantB(curveId, constant_b);

            // Initialize curve constant.
            _setMintConstantC(curveId, constant_c);
        }

        // Set mint status.
        _setCurveMintStatus(curveId, canMint);

        // Set treasury status.
        _setCurveTreasuryStatus(curveId, daoTreasury);

        return curveId;
    }

    /// -----------------------------------------------------------------------
    /// ImpactDAO memberships
    /// -----------------------------------------------------------------------

    /// @notice Summon an Impact DAO.
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
        if (amount == 0) revert InvalidAmount();

        deleteUnclaimed(msg.sender);

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /// -----------------------------------------------------------------------
    /// Patron Logic
    /// -----------------------------------------------------------------------

    /// @notice Donate to receive ImpactDAO tokens.
    function donate(uint256 curveId, address patron, uint256 donation) external payable initialized forSale(curveId) {
        // Retrieve current supply and mint price.
        uint256 supply = incrementCurveSupply(curveId);
        uint256 mintPrice = _getMintPrice(curveId, supply);

        // Validate mint conditions.
        if (donation != mintPrice) revert InvalidAmount();
        if (curveId == 0 || !this.getCurveMintStatus(curveId)) revert InvalidMint();

        // Retrieve current burn price.
        uint256 burnPrice = _getBurnPrice(curveId, supply);
        uint256 totalDonation;

        // Retrieve ImpactDAO and curve owner.
        address impactDAO = this.getImpactDao(curveId);
        address owner = this.getCurveOwner(curveId);

        // If ImpactDAO does not exist, summon one for curve owner and patron.
        if (impactDAO == address(0)) impactDAO = summonDao(curveId, owner, patron);

        // Confirm existing or recurring patron.
        if (IKaliTokenManager(impactDAO).balanceOf(patron) == 0) {
            // First time patrons receive one ether amount of ImpactDAO tokens.
            IKaliTokenManager(impactDAO).mintTokens(owner, 1 ether);
            IKaliTokenManager(impactDAO).mintTokens(patron, 1 ether);

            // Lock amount of burn price in contract to cover future burns.
            totalDonation = donation - burnPrice;
        } else {
            // Recurring patrons contribute entire donations.
            totalDonation = mintPrice;
        }

        // Distribute donation.
        if (this.getCurveTreasuryStatus(curveId)) {
            (bool success,) = payable(impactDAO).call{value: totalDonation}("");
            if (!success) addUnclaimed(impactDAO, totalDonation);
        } else {
            (bool success,) = owner.call{value: totalDonation}("");
            if (!success) addUnclaimed(owner, totalDonation);
        }
    }

    /// @notice Burn ImpactDAO tokens.
    function leave(uint256 curveId, address patron) external payable initialized {
        // Retrieve ImpactDAO and check if patron is eligible to leave.
        address impactDAO = this.getImpactDao(curveId);
        if (IKaliTokenManager(impactDAO).balanceOf(patron) == 0) revert InvalidBurn();

        // Retrieve current burn price.
        uint256 supply = this.getCurveSupply(curveId);
        uint256 price = _getBurnPrice(curveId, supply);
        // TODO: is this necessary
        if (price == 0) revert InvalidBurn();

        // Decrement supply.
        decrementCurveSupply(curveId);

        // Send burn price to patron.
        (bool success,) = patron.call{value: price}("");
        if (!success) addUnclaimed(patron, price);

        // Burn ImpactDAO tokens.
        IKaliTokenManager(impactDAO).burnTokens(this.getCurveOwner(curveId), 1 ether);
        IKaliTokenManager(impactDAO).burnTokens(patron, 1 ether);
    }

    /// -----------------------------------------------------------------------
    /// Setter Logic
    /// -----------------------------------------------------------------------

    function setKaliDaoFactory(address factory) external payable initialized onlyOperator {
        _setKaliDaoFactory(factory);
    }

    function _setKaliDaoFactory(address factory) internal {
        _setAddress(keccak256(abi.encodePacked("dao.factory")), factory);
    }

    function setImpactDao(uint256 curveId, address impactDao) internal {
        _setAddress(keccak256(abi.encode(curveId, ".impactDao")), impactDao);
    }

    function setCurveOwner(uint256 curveId, address owner) internal {
        if (owner == address(0)) revert NotAuthorized();
        _setAddress(keccak256(abi.encode(curveId, ".owner")), owner);
    }

    /// -----------------------------------------------------------------------
    /// Curve Setter Logic
    /// -----------------------------------------------------------------------

    function setMintConstantA(uint256 curveId, uint256 constant_a) external payable onlyOwner(curveId) {
        _setMintConstantA(curveId, constant_a);
    }

    function setMintConstantB(uint256 curveId, uint256 constant_b) external payable onlyOwner(curveId) {
        _setMintConstantB(curveId, constant_b);
    }

    function setMintConstantC(uint256 curveId, uint256 constant_c) external payable onlyOwner(curveId) {
        _setMintConstantC(curveId, constant_c);
    }

    // function setBurnConstantA(uint256 curveId, uint256 constant_a) external payable onlyOwner(curveId) {
    //     _setBurnConstantA(curveId, constant_a);
    // }

    // function setBurnConstantB(uint256 curveId, uint256 constant_b) external payable onlyOwner(curveId) {
    //     _setBurnConstantB(curveId, constant_b);
    // }

    // function setBurnConstantC(uint256 curveId, uint256 constant_c) external payable onlyOwner(curveId) {
    //     _setBurnConstantC(curveId, constant_c);
    // }

    function setCurveMintStatus(uint256 curveId, bool canMint) external payable onlyOwner(curveId) {
        _setCurveMintStatus(curveId, canMint);
    }

    function setCurveTreasuryStatus(uint256 curveId, bool daoTreasury) external payable onlyOwner(curveId) {
        _setCurveTreasuryStatus(curveId, daoTreasury);
    }

    function setCurveType(uint256 curveId, CurveType curveType) internal {
        _setUint(keccak256(abi.encode(curveId, ".curveType")), uint256(curveType));
    }

    function setCurveScale(uint256 curveId, uint256 scale) internal {
        if (scale == 0) revert InvalidCurveParam();
        _setUint(keccak256(abi.encode(curveId, ".scale")), scale);
    }

    function setCurveBurnRatio(uint256 curveId, uint256 burnRatio) internal {
        if (burnRatio == 0 || burnRatio > 100) revert InvalidCurveParam();
        _setUint(keccak256(abi.encode(curveId, ".burnRatio")), burnRatio);
    }

    function _setCurveMintStatus(uint256 curveId, bool canMint) internal {
        if (canMint != this.getCurveMintStatus(curveId)) _setBool(keccak256(abi.encode(curveId, ".canMint")), canMint);
    }

    function _setCurveTreasuryStatus(uint256 curveId, bool daoTreasury) internal {
        if (daoTreasury != this.getCurveTreasuryStatus(curveId)) {
            _setBool(keccak256(abi.encode(curveId, ".daoTreasury")), daoTreasury);
        }
    }

    function _setMintConstantA(uint256 curveId, uint256 constant_a) internal {
        // To prevent future calculation errors, such as arithmetic overflow/underflow.
        if (constant_a - this.getBurnConstantA(curveId) >= 0) {
            _setUint(keccak256(abi.encode(curveId, ".mint.a")), constant_a);
        } else {
            revert InvalidCurveParam();
        }
    }

    function _setMintConstantB(uint256 curveId, uint256 constant_b) internal {
        // To prevent future calculation errors, such as arithmetic overflow/underflow.
        if (constant_b - this.getBurnConstantB(curveId) >= 0) {
            _setUint(keccak256(abi.encode(curveId, ".mint.b")), constant_b);
        } else {
            revert InvalidCurveParam();
        }
    }

    function _setMintConstantC(uint256 curveId, uint256 constant_c) internal {
        // To prevent future calculation errors, such as arithmetic overflow/underflow.
        if (constant_c - this.getBurnConstantC(curveId) >= 0) {
            _setUint(keccak256(abi.encode(curveId, ".mint.c")), constant_c);
        } else {
            revert InvalidCurveParam();
        }
    }

    // function _setBurnConstantA(uint256 curveId, uint256 constant_a) internal {
    //     // To prevent future calculation errors, such as arithmetic overflow/underflow.
    //     if (this.getMintConstantA(curveId) - constant_a >= 0) {
    //         _setUint(keccak256(abi.encode(curveId, ".burn.a")), constant_a);
    //     } else {
    //         revert InvalidCurveParam();
    //     }
    // }

    // function _setBurnConstantB(uint256 curveId, uint256 constant_b) internal {
    //     // To prevent future calculation errors, such as arithmetic overflow/underflow.
    //     if (this.getMintConstantB(curveId) - constant_b >= 0) {
    //         _setUint(keccak256(abi.encode(curveId, ".burn.b")), constant_b);
    //     } else {
    //         revert InvalidCurveParam();
    //     }
    // }

    // function _setBurnConstantC(uint256 curveId, uint256 constant_c) internal {
    //     // To prevent future calculation errors, such as arithmetic overflow/underflow.
    //     if (this.getMintConstantC(curveId) - constant_c >= 0) {
    //         _setUint(keccak256(abi.encode(curveId, ".burn.c")), constant_c);
    //     } else {
    //         revert InvalidCurveParam();
    //     }
    // }
    /// -----------------------------------------------------------------------
    /// Getter Logic
    /// -----------------------------------------------------------------------

    function getKaliDaoFactory() external view returns (address) {
        return this.getAddress(keccak256(abi.encodePacked("dao.factory")));
    }

    function getCurveCount() external view returns (uint256) {
        return this.getUint(keccak256(abi.encodePacked("curves.count")));
    }

    function getImpactDao(uint256 curveId) external view returns (address) {
        return this.getAddress(keccak256(abi.encode(curveId, ".impactDao")));
    }

    /// -----------------------------------------------------------------------
    /// Curve Getter Logic
    /// -----------------------------------------------------------------------

    function getCurveSupply(uint256 curveId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(curveId, ".supply")));
    }

    function getCurveMintStatus(uint256 curveId) external view returns (bool) {
        return this.getBool(keccak256(abi.encode(curveId, ".canMint")));
    }

    function getCurveTreasuryStatus(uint256 curveId) external view returns (bool) {
        return this.getBool(keccak256(abi.encode(curveId, ".daoTreasury")));
    }

    function getCurveType(uint256 curveId) external view returns (CurveType) {
        return CurveType(this.getUint(keccak256(abi.encode(curveId, ".curveType"))));
    }

    function getCurveScale(uint256 curveId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(curveId, ".scale")));
    }

    function getCurveBurnRatio(uint256 curveId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(curveId, ".burnRatio")));
    }

    function getMintConstantA(uint256 curveId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(curveId, ".mint.a")));
    }

    function getMintConstantB(uint256 curveId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(curveId, ".mint.b")));
    }

    function getMintConstantC(uint256 curveId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(curveId, ".mint.c")));
    }

    // TODO: Modify per ratio
    function getBurnConstantA(uint256 curveId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(curveId, ".burn.a")));
    }

    function getBurnConstantB(uint256 curveId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(curveId, ".burn.b")));
    }

    function getBurnConstantC(uint256 curveId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(curveId, ".burn.c")));
    }

    // mint formula - initMintPrice + supply * initMintPrice / 50 + (supply ** 2) * initMintPrice / 100;
    // burn formula - initMintPrice + supply * initMintPrice / 50 + (supply ** 2) * initMintPrice / 200;

    /// @notice Calculate mint price.
    function getMintPrice(uint256 curveId) external view returns (uint256) {
        uint256 supply = this.getCurveSupply(curveId);
        return _getMintPrice(curveId, ++supply);
    }

    /// @notice Calculate mint price.
    function _getMintPrice(uint256 curveId, uint256 supply) internal view returns (uint256) {
        CurveType curveType = this.getCurveType(curveId);
        if (curveType == CurveType.NA) return 0;

        // Retrieve constants.
        uint256 scale = this.getCurveScale(curveId);
        uint256 constant_a = this.getMintConstantA(curveId);
        uint256 constant_b = this.getMintConstantB(curveId);
        uint256 constant_c = this.getMintConstantC(curveId);

        // Return linear pricing based on, a * b * x + b.
        if (curveType == CurveType.LINEAR) {
            return constant_a * supply * scale + constant_b * scale;
        } else {
            // Return curve pricing based on, a * c * x^2 + b * c * x + c.
            return constant_a * (supply ** 2) * scale + constant_b * supply * scale + constant_c * scale;
        }
    }

    /// @notice Calculate burn price.
    function getBurnPrice(uint256 curveId) external view returns (uint256) {
        uint256 supply = this.getCurveSupply(curveId);
        return _getBurnPrice(curveId, supply);
    }
    /// @notice Calculate burn price.

    function _getBurnPrice(uint256 curveId, uint256 supply) internal view returns (uint256) {
        CurveType curveType = this.getCurveType(curveId);
        if (curveType == CurveType.NA) return 0;

        // Retrieve constants.
        uint256 scale = this.getCurveScale(curveId);
        uint256 constant_a = this.getBurnConstantA(curveId);
        uint256 constant_b = this.getBurnConstantB(curveId);
        uint256 constant_c = this.getBurnConstantC(curveId);

        // Return linear pricing based on, a * b * x + b.
        if (curveType == CurveType.LINEAR) {
            return constant_a * supply * scale + constant_b * scale;
        } else {
            // Return curve pricing based on, a * c * x^2 + b * c * x + c.
            return constant_a * (supply ** 2) * scale + constant_b * supply * scale + constant_c * scale;
        }
    }

    // function getMintBurnDifference(uint256 curveId) external view returns (uint256) {
    //     return this.getMintPrice(curveId) - this.getBurnPrice(curveId);
    // }

    function getCurveOwner(uint256 curveId) external view returns (address) {
        return this.getAddress(keccak256(abi.encode(curveId, ".owner")));
    }

    // TODO: Consider adding a get function ownerCurves array

    function getUnclaimed(address user) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(user, ".unclaimed")));
    }

    /// -----------------------------------------------------------------------
    /// Add Logic
    /// -----------------------------------------------------------------------

    function addUnclaimed(address user, uint256 amount) internal returns (uint256) {
        return addUint(keccak256(abi.encode(user, ".unclaimed")), amount);
    }

    function incrementCurveSupply(uint256 curveId) internal returns (uint256) {
        return addUint(keccak256(abi.encodePacked(curveId, ".supply")), 1);
    }

    function decrementCurveSupply(uint256 curveId) internal returns (uint256) {
        return subUint(keccak256(abi.encodePacked(curveId, ".supply")), 1);
    }

    function incrementCurveId() internal returns (uint256) {
        return addUint(keccak256(abi.encodePacked("curves.count")), 1);
    }

    /// -----------------------------------------------------------------------
    /// Delete Logic
    /// -----------------------------------------------------------------------

    function deleteUnclaimed(address user) internal {
        deleteUint(keccak256(abi.encode(user, ".unclaimed")));
    }

    function deleteCurvePurchaseStatus(uint256 curveId) internal {
        deleteBool(keccak256(abi.encode(curveId, ".forSale")));
    }

    /// -----------------------------------------------------------------------
    /// ERC721 Logic
    /// -----------------------------------------------------------------------

    /// @notice Interface for any contract that wants to support safeTransfers from ERC721 asset contracts.
    /// credit: z0r0z.eth https://github.com/kalidao/kali-contracts/blob/main/contracts/utils/NFTreceiver.sol
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4 sig) {
        sig = 0x150b7a02; // 'onERC721Received(address,address,uint256,bytes)'
    }

    receive() external payable virtual {}
}
