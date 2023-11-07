// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

import {LibString} from "solbase/utils/LibString.sol";
import {IERC721} from "forge-std/interfaces/IERC721.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IStorage} from "./interface/IStorage.sol";
import {Storage} from "./Storage.sol";

import {IPatronCertificate} from "./interface/IPatronCertificate.sol";

import {KaliDAOfactory} from "./kalidao/KaliDAOfactory.sol";
import {IKaliTokenManager} from "./interface/IKaliTokenManager.sol";

/// @notice When DAOs use Harberger Tax to sell goods and services and
///         automagically form treasury subDAOs, good things happen!
/// @author audsssy.eth
contract KaliBerger is Storage {
    /// -----------------------------------------------------------------------
    /// Custom Error
    /// -----------------------------------------------------------------------

    error NotAuthorized();
    error TransferFailed();
    error InvalidExit();
    error NotInitialized();
    error InvalidAmount();

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    function initialize(address dao, address daoFactory, address minter) external {
        if (daoFactory != address(0)) {
            init(dao);
            _setKaliDaoFactory(daoFactory);
            _setCertificateMinter(minter);
        }
    }

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    modifier initialized() {
        if (
            this.getKaliDaoFactory() == address(0) || this.getDao() == address(0)
                || this.getCertificateMinter() == address(0)
        ) revert NotInitialized();
        _;
    }

    modifier onlyOwner(address token, uint256 tokenId) {
        if (this.getOwner(token, tokenId) != msg.sender) revert NotAuthorized();
        _;
    }

    modifier collectPatronage(address token, uint256 tokenId) {
        _collectPatronage(token, tokenId);
        _;
    }

    modifier forSale(address token, uint256 tokenId) {
        if (!this.getTokenPurchaseStatus(token, tokenId)) revert NotInitialized();
        _;
    }

    /// -----------------------------------------------------------------------
    /// Creator Logic
    /// -----------------------------------------------------------------------

    /// @notice Escrow ERC721 NFT before making it available for purchase.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    function escrow(address token, uint256 tokenId, address creator) external payable {
        // Confirm msg.sender is creator and owner of token
        if (IERC721(token).ownerOf(tokenId) != msg.sender) revert NotAuthorized();

        // Transfer ERC721 to KaliBerger
        IERC721(token).safeTransferFrom(msg.sender, address(this), tokenId);

        // Set creator
        setCreator(token, tokenId, creator);
    }

    /// @notice Pull ERC721 NFT from escrow when it is idle.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    function pull(address token, uint256 tokenId) external payable collectPatronage(token, tokenId) {
        address minter = this.getCertificateMinter();
        uint256 id = IPatronCertificate(minter).getTokenId(token, tokenId);

        // Confirm msg.sender is creator and owner of certificate is address(this)
        if (this.getCreator(token, tokenId) != msg.sender) revert NotAuthorized();
        if (IPatronCertificate(minter).ownerOf(id) != address(this)) revert InvalidExit();

        // Transfer ERC721 back to creator
        IERC721(token).safeTransferFrom(address(this), msg.sender, tokenId);

        deleteTokenPurchaseStatus(token, tokenId);
        // TODO: Consider selfdestruct ImpactDAO
    }

    /// -----------------------------------------------------------------------
    /// DAO Logic
    /// -----------------------------------------------------------------------

    /// @notice Approve ERC721 NFT for purchase.
    /// @dev note ERC721 tokenId is downcast to uint96 for minting patron certificates
    /// @dev note Potential id collision may occur depending on ERC721 tokenId assignment logic
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param sale Confirm or reject use of Harberger Tax for escrowed ERC721.
    function approve(address token, uint256 tokenId, bool sale, string calldata detail)
        external
        payable
        initialized
        onlyOperator
    {
        if (IERC721(token).ownerOf(tokenId) != address(this)) revert NotAuthorized();
        address owner = this.getCreator(token, tokenId);

        if (!sale) {
            IERC721(token).safeTransferFrom(address(this), owner, tokenId);
        } else {
            // Mint a certificate as proof of ownership.
            // Can use to redeem escrowed artwork anytime.
            address pc = this.getCertificateMinter();
            IPatronCertificate(pc).mint(owner, IPatronCertificate(pc).getTokenId(token, tokenId));

            // Initialize conditions
            setTimeLastCollected(token, tokenId, block.timestamp);
            setTimeAcquired(token, tokenId, block.timestamp);
            setOwner(token, tokenId, address(this));
            if (sale) setTokenPurchaseStatus(token, tokenId, sale);
            _setTokenDetail(token, tokenId, detail);
        }
    }

    /// -----------------------------------------------------------------------
    /// ImpactDAO memberships
    /// -----------------------------------------------------------------------

    /// @notice Public function to rebalance any Impact DAO.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    function balanceDao(address token, uint256 tokenId) external payable collectPatronage(token, tokenId) {
        _balance(token, tokenId, this.getImpactDao(token, tokenId));
    }

    /// @notice Update Impact DAO balance when ERC721 is purchased.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param patron Patron of ERC721.
    function updateBalances(address token, uint256 tokenId, address impactDao, address patron) internal {
        if (impactDao == address(0)) {
            // Summon DAO with 50/50 ownership between creator and patron(s).
            setImpactDao(token, tokenId, summonDao(token, tokenId, this.getCreator(token, tokenId), patron));
        } else {
            // Update DAO balance.
            _balance(token, tokenId, impactDao);
        }
    }

    /// @notice Summon an Impact DAO.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param creator Creator of ERC721.
    /// @param patron Patron of ERC721.
    function summonDao(address token, uint256 tokenId, address creator, address patron) private returns (address) {
        // Provide creator and patron to summon DAO.
        address[] memory voters = new address[](2);
        voters[0] = creator;
        voters[1] = patron;

        // Provide respective token amount.
        uint256[] memory tokens = new uint256[](2);
        tokens[0] = this.getPatronContribution(token, tokenId, patron);
        tokens[1] = tokens[0];

        // Provide KaliBerger as extension.
        address[] memory extensions = new address[](1);
        extensions[0] = address(this);
        bytes[] memory extensionsData = new bytes[](1);
        extensionsData[0] = "0x0";

        // Provide KaliDAO governance settings.
        uint32[16] memory govSettings;
        govSettings = [uint32(86400), 0, 20, 60, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];

        // Summon a KaliDAO
        uint256 count = this.getBergerCount();
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

        // Store dao address for future.
        setImpactDao(token, tokenId, impactDao);

        // Increment number of impactDAOs.
        incrementBergerCount();
        return impactDao;
    }

    /// @notice Rebalance Impact DAO.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param dao ImpactDAO summoned for ERC721.
    function _balance(address token, uint256 tokenId, address dao) private {
        uint256 count = this.getPatronCount(token, tokenId);
        address creator = this.getCreator(token, tokenId);

        // Balance token amount per patron.
        for (uint256 i = 1; i <= count;) {
            // Retrieve patron and patron contribution.
            address _patron = this.getPatron(token, tokenId, i);
            uint256 contribution = this.getPatronContribution(token, tokenId, _patron);

            // Retrieve KaliDAO balance data.
            uint256 _contribution = IERC20(dao).balanceOf(_patron);

            // Determine to mint or burn.
            if (contribution > _contribution) {
                IKaliTokenManager(dao).mintTokens(creator, contribution - _contribution);
                IKaliTokenManager(dao).mintTokens(_patron, contribution - _contribution);
            } else if (contribution < _contribution) {
                IKaliTokenManager(dao).burnTokens(_patron, (_contribution - contribution));
            }

            unchecked {
                ++i;
            }
        }

        uint256 creatorBalance = IERC20(dao).balanceOf(creator);
        uint256 totalCollected = this.getTotalCollected(token, tokenId);

        // Balance creator token amount.
        if (creatorBalance > totalCollected) {
            IKaliTokenManager(dao).burnTokens(creator, creatorBalance - totalCollected);
        } else if (totalCollected > creatorBalance) {
            IKaliTokenManager(dao).mintTokens(creator, totalCollected - creatorBalance);
        }
    }

    /// -----------------------------------------------------------------------
    /// Unclaimed Logic
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

    /// @notice Buy Patron Certificate.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param newPrice New purchase price for ERC721.
    /// @param currentPrice Current purchase price for ERC721.
    function buy(address token, uint256 tokenId, uint256 newPrice, uint256 currentPrice)
        external
        payable
        initialized
        forSale(token, tokenId)
        collectPatronage(token, tokenId)
    {
        address owner = this.getOwner(token, tokenId);

        // Pay currentPrice + deposit to current owner.
        processPayment(token, tokenId, owner, newPrice, currentPrice);

        // Transfer ERC721 NFT and update price, ownership, and patron data.
        transferPatronCertificate(token, tokenId, owner, msg.sender, newPrice);

        // Balance DAO according to updated contribution.
        updateBalances(token, tokenId, this.getImpactDao(token, tokenId), msg.sender);
    }

    /// @notice Set new price for purchase.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param price New purchase price for ERC721.
    function setPrice(address token, uint256 tokenId, uint256 price)
        external
        payable
        onlyOwner(token, tokenId)
        collectPatronage(token, tokenId)
    {
        if (price > 0) _setPrice(token, tokenId, price);
    }

    /// @notice Make a deposit.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    function addDeposit(address token, uint256 tokenId, uint256 amount)
        external
        payable
        collectPatronage(token, tokenId)
    {
        if (amount != msg.value) revert InvalidAmount();
        _addDeposit(token, tokenId, msg.value);
    }

    /// @notice Withdraw from deposit.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param amount Amount to withdraw from deposit.
    function exit(address token, uint256 tokenId, uint256 amount)
        public
        collectPatronage(token, tokenId)
        onlyOwner(token, tokenId)
    {
        if (amount > this.getDeposit(token, tokenId)) revert InvalidExit();
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) addUnclaimed(msg.sender, amount);

        subDeposit(token, tokenId, amount);
    }

    /// -----------------------------------------------------------------------
    /// Setter Logic
    /// -----------------------------------------------------------------------

    function setKaliDaoFactory(address factory) external payable initialized onlyOperator {
        _setAddress(keccak256(abi.encodePacked("dao.factory")), factory);
    }

    function setCertificateMinter(address factory) external payable initialized onlyOperator {
        _setAddress(keccak256(abi.encodePacked("certificate.minter")), factory);
    }

    function setTax(address token, uint256 tokenId, uint256 _tax)
        external
        payable
        initialized
        onlyOperator
        collectPatronage(token, tokenId)
    {
        if (_tax > 100) revert InvalidAmount();
        _setUint(keccak256(abi.encode(token, tokenId, ".tax")), _tax);
    }

    function setTokenDetail(address token, uint256 tokenId, string calldata detail)
        external
        payable
        initialized
        onlyOperator
    {
        if (this.getOwner(token, tokenId) == address(0)) revert NotInitialized();
        _setString(keccak256(abi.encode(token, tokenId, ".detail")), detail);
    }

    function _setKaliDaoFactory(address factory) internal {
        _setAddress(keccak256(abi.encodePacked("dao.factory")), factory);
    }

    function _setCertificateMinter(address factory) internal {
        _setAddress(keccak256(abi.encodePacked("certificate.minter")), factory);
    }

    function setImpactDao(address token, uint256 tokenId, address impactDao) internal {
        _setAddress(keccak256(abi.encode(token, tokenId, ".impactDao")), impactDao);
    }

    function setCreator(address token, uint256 tokenId, address creator) internal {
        _setAddress(keccak256(abi.encode(token, tokenId, ".creator")), creator);
    }

    function _setTokenDetail(address token, uint256 tokenId, string calldata detail) internal {
        if (bytes(detail).length > 0) _setString(keccak256(abi.encode(token, tokenId, ".detail")), detail);
    }

    function setTokenPurchaseStatus(address token, uint256 tokenId, bool _forSale) internal {
        _setBool(keccak256(abi.encode(token, tokenId, ".forSale")), _forSale);
    }

    function _setPrice(address token, uint256 tokenId, uint256 price) internal {
        _setUint(keccak256(abi.encode(token, tokenId, ".price")), price);
    }

    function setTimeLastCollected(address token, uint256 tokenId, uint256 timestamp) internal {
        _setUint(keccak256(abi.encode(token, tokenId, ".timeLastCollected")), timestamp);
    }

    function setTimeAcquired(address token, uint256 tokenId, uint256 timestamp) internal {
        _setUint(keccak256(abi.encode(token, tokenId, ".timeAcquired")), timestamp);
    }

    function setOwner(address token, uint256 tokenId, address owner) internal {
        _setAddress(keccak256(abi.encode(token, tokenId, ".owner")), owner);
    }

    function setPatron(address token, uint256 tokenId, address patron) internal {
        _setAddress(keccak256(abi.encode(token, tokenId, ".patrons.", incrementPatronId(token, tokenId))), patron);
    }

    function setPatronStatus(address token, uint256 tokenId, address patron, bool status) internal {
        _setBool(keccak256(abi.encode(token, tokenId, ".isPatron.", patron)), status);
    }

    /// -----------------------------------------------------------------------
    /// Getter Logic
    /// -----------------------------------------------------------------------

    function getKaliDaoFactory() external view returns (address) {
        return this.getAddress(keccak256(abi.encodePacked("dao.factory")));
    }

    function getCertificateMinter() external view returns (address) {
        return this.getAddress(keccak256(abi.encodePacked("certificate.minter")));
    }

    function getBergerCount() external view returns (uint256) {
        return this.getUint(keccak256(abi.encodePacked("bergerTimes.count")));
    }

    function getImpactDao(address token, uint256 tokenId) external view returns (address) {
        return this.getAddress(keccak256(abi.encode(token, tokenId, ".impactDao")));
    }

    function getTokenPurchaseStatus(address token, uint256 tokenId) external view returns (bool) {
        return this.getBool(keccak256(abi.encode(token, tokenId, ".forSale")));
    }

    function getTax(address token, uint256 tokenId) external view returns (uint256 _tax) {
        _tax = this.getUint(keccak256(abi.encode(token, tokenId, ".tax")));
        return (_tax == 0) ? _tax = 10 : _tax; // default tax rate is hardcoded to 10%
    }

    function getPrice(address token, uint256 tokenId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(token, tokenId, ".price")));
    }

    function getCreator(address token, uint256 tokenId) external view returns (address) {
        return this.getAddress(keccak256(abi.encode(token, tokenId, ".creator")));
    }

    function getTokenDetail(address token, uint256 tokenId) external view returns (string memory) {
        return this.getString(keccak256(abi.encode(token, tokenId, ".detail")));
    }

    function getDeposit(address token, uint256 tokenId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(token, tokenId, ".deposit")));
    }

    function getTimeLastCollected(address token, uint256 tokenId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(token, tokenId, ".timeLastCollected")));
    }

    function getTimeAcquired(address token, uint256 tokenId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(token, tokenId, ".timeAcquired")));
    }

    function getUnclaimed(address user) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(user, ".unclaimed")));
    }

    function getTimeHeld(address user) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(user, ".timeHeld")));
    }

    function getTotalCollected(address token, uint256 tokenId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(token, tokenId, ".totalCollected")));
    }

    function getOwner(address token, uint256 tokenId) external view returns (address) {
        return this.getAddress(keccak256(abi.encode(token, tokenId, ".owner")));
    }

    function getPatronCount(address token, uint256 tokenId) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(token, tokenId, ".patrons.count")));
    }

    function getPatronId(address token, uint256 tokenId, address patron) external view returns (uint256) {
        uint256 count = this.getPatronCount(token, tokenId);

        for (uint256 i = 0; i <= count;) {
            if (patron == this.getPatron(token, tokenId, i)) return i;
            unchecked {
                ++i;
            }
        }

        return 0;
    }

    function isPatron(address token, uint256 tokenId, address patron) external view returns (bool) {
        return this.getBool(keccak256(abi.encode(token, tokenId, ".isPatron.", patron)));
    }

    function getPatron(address token, uint256 tokenId, uint256 patronId) external view returns (address) {
        return this.getAddress(keccak256(abi.encode(token, tokenId, ".patrons.", patronId)));
    }

    function getPatronContribution(address token, uint256 tokenId, address patron) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(token, tokenId, patron, ".contribution")));
    }

    /// -----------------------------------------------------------------------
    /// Add Logic
    /// -----------------------------------------------------------------------

    function _addDeposit(address token, uint256 tokenId, uint256 amount) internal {
        addUint(keccak256(abi.encode(token, tokenId, ".deposit")), amount);
    }

    function subDeposit(address token, uint256 tokenId, uint256 amount) internal {
        subUint(keccak256(abi.encode(token, tokenId, ".deposit")), amount);
    }

    function addUnclaimed(address user, uint256 amount) internal {
        addUint(keccak256(abi.encode(user, ".unclaimed")), amount);
    }

    function addTimeHeld(address user, uint256 time) internal {
        addUint(keccak256(abi.encode(user, ".timeHeld")), time);
    }

    function addTotalCollected(address token, uint256 tokenId, uint256 collected) internal {
        addUint(keccak256(abi.encode(token, tokenId, ".totalCollected")), collected);
    }

    function addPatronContribution(address token, uint256 tokenId, address patron, uint256 amount) internal {
        addUint(keccak256(abi.encode(token, tokenId, patron, ".contribution")), amount);
    }

    function incrementBergerCount() internal {
        addUint(keccak256(abi.encodePacked("bergerTimes.count")), 1);
    }

    function incrementPatronId(address token, uint256 tokenId) internal returns (uint256) {
        return addUint(keccak256(abi.encode(token, tokenId, ".patrons.count")), 1);
    }

    /// -----------------------------------------------------------------------
    /// Delete Logic
    /// -----------------------------------------------------------------------

    // function deletePrice(address token, uint256 tokenId) internal {
    //     deleteUint(keccak256(abi.encode(token, tokenId, ".price")));
    // }

    function deleteDeposit(address token, uint256 tokenId) internal {
        deleteUint(keccak256(abi.encode(token, tokenId, ".deposit")));
    }

    function deleteUnclaimed(address user) internal {
        deleteUint(keccak256(abi.encode(user, ".unclaimed")));
    }

    function deleteTokenPurchaseStatus(address token, uint256 tokenId) internal {
        deleteBool(keccak256(abi.encode(token, tokenId, ".forSale")));
    }

    /// -----------------------------------------------------------------------
    /// Collection Logic
    /// -----------------------------------------------------------------------

    // credit: simondlr  https://github.com/simondlr/thisartworkisalwaysonsale/blob/master/packages/hardhat/contracts/v1/ArtStewardV2.sol
    function patronageToCollect(address token, uint256 tokenId) external view returns (uint256 amount) {
        return this.getPrice(token, tokenId) * (block.timestamp - this.getTimeLastCollected(token, tokenId))
            * this.getTax(token, tokenId) / 365 days / 100;
    }

    /// -----------------------------------------------------------------------
    /// Foreclosure Logic
    /// -----------------------------------------------------------------------

    // credit: simondlr  https://github.com/simondlr/thisartworkisalwaysonsale/blob/master/packages/hardhat/contracts/v1/ArtStewardV2.sol
    // function isForeclosed(address token, uint256 tokenId) external view returns (bool, uint256) {
    //     // returns whether it is in foreclosed state or not
    //     // depending on whether deposit covers patronage due
    //     // useful helper function when price should be zero, but contract doesn't reflect it yet.
    //     uint256 toCollect = this.patronageToCollect(token, tokenId);
    //     uint256 _deposit = this.getDeposit(token, tokenId);
    //     if (toCollect >= _deposit) {
    //         return (true, 0);
    //     } else {
    //         return (false, _deposit - toCollect);
    //     }
    // }

    // credit: simondlr  https://github.com/simondlr/thisartworkisalwaysonsale/blob/master/packages/hardhat/contracts/v1/ArtStewardV2.sol
    // function foreclosureTime(address token, uint256 tokenId) external view returns (uint256) {
    //     uint256 pps = this.getPrice(token, tokenId) / 365 days * (this.getTax(token, tokenId) / 100);
    //     (, uint256 daw) = this.isForeclosed(token, tokenId);
    //     if (daw > 0) {
    //         return block.timestamp + daw / pps;
    //     } else if (pps > 0) {
    //         // it is still active, but in foreclosure state
    //         // it is block.timestamp or was in the pas
    //         // not active and actively foreclosed (price is zero)
    //         uint256 timeLastCollected = this.getTimeLastCollected(token, tokenId);
    //         return timeLastCollected
    //             + (block.timestamp - timeLastCollected) * this.getDeposit(token, tokenId)
    //                 / this.patronageToCollect(token, tokenId);
    //     } else {
    //         // not active and actively foreclosed (price is zero)
    //         return this.getTimeLastCollected(token, tokenId); // it has been foreclosed or in foreclosure.
    //     }
    // }

    /// @notice Internal function to collect patronage.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// credit: simondlr  https://github.com/simondlr/thisartworkisalwaysonsale/blob/master/packages/hardhat/contracts/v1/ArtStewardV2.sol
    function _collectPatronage(address token, uint256 tokenId) internal {
        uint256 price = this.getPrice(token, tokenId);
        uint256 toCollect = this.patronageToCollect(token, tokenId);
        uint256 deposit = this.getDeposit(token, tokenId);
        uint256 timeLastCollected = this.getTimeLastCollected(token, tokenId);

        if (price != 0) {
            // price > 0 == active owned state
            if (toCollect > deposit) {
                if (deposit > 0) {
                    // foreclosure happened in the past
                    // up to when was it actually paid for?
                    // TLC + (time_elapsed)*deposit/toCollect
                    setTimeLastCollected(token, tokenId, (block.timestamp - timeLastCollected) * deposit / toCollect);

                    // Add to unclaimed pool for corresponding impactDao to claim at later time.
                    addUnclaimed(this.getImpactDao(token, tokenId), deposit);

                    // Add to total amount collected.
                    addTotalCollected(token, tokenId, deposit);

                    // Add to amount collected by patron.
                    addPatronContribution(token, tokenId, this.getOwner(token, tokenId), deposit);
                }

                // Foreclose.
                _foreclose(token, tokenId);
            } else {
                // Normal collection.
                setTimeLastCollected(token, tokenId, block.timestamp);

                // Add to unclaimed pool for corresponding impactDao to claim at later time.
                if (toCollect != 0) {
                    addUnclaimed(this.getImpactDao(token, tokenId), toCollect);
                    subDeposit(token, tokenId, toCollect);
                }

                // Add to total amount collected.
                addTotalCollected(token, tokenId, toCollect);

                // Add to amount collected by patron.
                addPatronContribution(token, tokenId, this.getOwner(token, tokenId), toCollect);
            }
        }
    }

    /// @notice Internal function to foreclose.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    function _foreclose(address token, uint256 tokenId) internal {
        transferPatronCertificate(token, tokenId, address(0), address(this), 0);
        deleteDeposit(token, tokenId);
    }

    /// -----------------------------------------------------------------------
    /// NFT Transfer & Payments Logic
    /// -----------------------------------------------------------------------

    /// @notice Internal function to transfer ERC721.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param currentOwner Current owner of ERC721.
    /// @param newOwner New owner of ERC721.
    /// @param price Price of ERC721.
    // credit: simondlr  https://github.com/simondlr/thisartworkisalwaysonsale/blob/master/packages/hardhat/contracts/v1/ArtStewardV2.sol
    function transferPatronCertificate(
        address token,
        uint256 tokenId,
        address currentOwner,
        address newOwner,
        uint256 price
    ) internal {
        address minter = this.getCertificateMinter();
        uint256 _tokenId = IPatronCertificate(minter).getTokenId(token, tokenId);
        uint256 timeAcquired = this.getTimeAcquired(token, tokenId);
        uint256 timeLastCollected = this.getTimeLastCollected(token, tokenId);

        if (currentOwner == address(0)) {
            // Foreclose.
            currentOwner = IPatronCertificate(minter).ownerOf(_tokenId);
        }

        // Calculate absolute time held by current owner, including KaliBerger.
        addTimeHeld(
            currentOwner,
            (timeLastCollected > timeAcquired) ? timeLastCollected - timeAcquired : timeAcquired - timeLastCollected
        );

        // Otherwise transfer ownership.
        IPatronCertificate(minter).safeTransferFrom(currentOwner, newOwner, _tokenId);

        // Set new owner
        setOwner(token, tokenId, newOwner);

        // Update new price.
        _setPrice(token, tokenId, price);

        // Update time of acquisition.
        setTimeAcquired(token, tokenId, block.timestamp);

        // Add new owner as patron.
        setPatron(token, tokenId, newOwner);

        // Toggle new owner's patron status.
        setPatronStatus(token, tokenId, newOwner, true);
    }

    /// @notice Process purchase payment.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param currentOwner Current owner of ERC721.
    /// @param newPrice New price of ERC721.
    /// @param currentPrice Current price of ERC721.
    /// credit: simondlr  https://github.com/simondlr/thisartworkisalwaysonsale/blob/master/packages/hardhat/contracts/v1/ArtStewardV2.sol
    function processPayment(
        address token,
        uint256 tokenId,
        address currentOwner,
        uint256 newPrice,
        uint256 currentPrice
    ) internal {
        // Confirm price.
        uint256 price = this.getPrice(token, tokenId);
        if (price != currentPrice || newPrice == 0 || currentPrice > msg.value) revert InvalidAmount();

        // Add purchase price to patron contribution.
        // addPatronContribution(token, tokenId, msg.sender, price);

        // Retrieve deposit, if any.
        uint256 deposit = this.getDeposit(token, tokenId);

        if (price + deposit > 0) {
            // this won't execute if KaliBerger owns it. price = 0. deposit = 0.
            // pay previous owner their price + deposit back.
            (bool success,) = currentOwner.call{value: price + deposit}("");
            if (!success) addUnclaimed(currentOwner, price + deposit);
            deleteDeposit(token, tokenId);
        }

        // Make deposit, if any.
        _addDeposit(token, tokenId, msg.value - price);
    }

    /// @notice Interface for any contract that wants to support safeTransfers from ERC721 asset contracts.
    /// credit: z0r0z.eth https://github.com/kalidao/kali-contracts/blob/main/contracts/utils/NFTreceiver.sol
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4 sig) {
        sig = 0x150b7a02; // 'onERC721Received(address,address,uint256,bytes)'
    }

    receive() external payable virtual {}
}
