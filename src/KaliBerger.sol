// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

import {LibString} from "../lib/solbase/src/utils/LibString.sol";
// import {SafeTransferLib} from "../lib/solbase/src/utils/SafeTransferLib.sol";

import {IStorage} from "./interface/IStorage.sol";
import {Storage} from "./Storage.sol";

import {KaliDAOfactory} from "./kalidao/KaliDAOfactory.sol";
import {KaliDAO} from "./kalidao/KaliDAO.sol";
import {IKaliTokenManager} from "./interface/IKaliTokenManager.sol";

import {IERC721} from "../lib/forge-std/src/interfaces/IERC721.sol";
import {IERC20} from "../lib/forge-std/src/interfaces/IERC20.sol";

/// @notice When DAOs use Harberger Tax to sell goods and services and
///         automagically form treasury subDAOs, good things happen!
/// @author audsssy.eth
contract KaliBerger is Storage {
    /// -----------------------------------------------------------------------
    /// Custom Error
    /// -----------------------------------------------------------------------

    error NotAuthorized();
    error TransferFailed();
    error InvalidPrice();
    error InvalidExit();
    error NotPatron();
    error NotInitialized();
    error InvalidPurchase();
    error InvalidClaim();
    error InvalidAmount();

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    function initialize(address dao, address factory) external {
        if (factory != address(0)) {
            init(dao, address(0));
            this.setKaliDaoFactory(factory);
        }
    }

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    modifier onlyPatron(address token, uint256 tokenId) {
        if (!this.isPatron(token, tokenId, msg.sender)) revert NotPatron();
        _;
    }

    modifier collectPatronage(address token, uint256 tokenId) {
        _collectPatronage(token, tokenId);
        _;
    }

    modifier initialized() {
        if (this.getKaliDaoFactory() == address(0) || this.getDao() == address(0)) revert NotInitialized();
        _;
    }

    modifier forSale(address token, uint256 tokenId) {
        if (!this.getTokenStatus(token, tokenId)) revert NotInitialized();
        _;
    }

    /// -----------------------------------------------------------------------
    /// Confirm Sale with Harberger Tax
    /// -----------------------------------------------------------------------

    /// @notice Escrow ERC721 NFT before making it available for purchase.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    function escrow(address token, uint256 tokenId) external payable {
        // Confirm msg.sender is owner of token
        address owner = IERC721(token).ownerOf(tokenId);
        if (owner != msg.sender) revert NotAuthorized();

        // Transfer ERC721 to KaliBerger
        IERC721(token).safeTransferFrom(msg.sender, address(this), tokenId);

        // Set creator
        this.setCreator(token, tokenId, owner);
    }

    /// @notice Approve ERC721 NFT for purchase.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param sale Confirm or reject use of Harberger Tax for escrowed ERC721.
    function approve(address token, uint256 tokenId, bool sale, string calldata detail) external payable onlyOperator {
        if (IERC721(token).ownerOf(tokenId) != address(this)) revert NotAuthorized();

        if (!sale) {
            IERC721(token).safeTransferFrom(address(this), this.getCreator(token, tokenId), tokenId);
        } else {
            setTokenPurchaseStatus(token, tokenId, sale);
            setTimeLastCollected(token, tokenId, block.timestamp);
            setTimeAcquired(token, tokenId, block.timestamp);
            setTokenDetail(token, tokenId, detail);
            setOwner(token, tokenId, address(this));
        }
    }

    /// -----------------------------------------------------------------------
    /// ImpactDAO memberships
    /// -----------------------------------------------------------------------

    /// @notice Public function to rebalance an Impact DAO.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    function balanceDao(address token, uint256 tokenId) external payable {
        // Get address to DAO to manage revenue from Harberger Tax
        address dao = this.getImpactDao(token, tokenId);
        if (dao == address(0)) revert NotAuthorized();

        _balance(token, tokenId, dao);
    }

    /// @notice Summon an Impact DAO
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param creator Creator of ERC721.
    /// @param patron Patron of ERC721.
    function summonDao(address token, uint256 tokenId, address creator, address patron) private returns (address) {
        address[] memory extensions;
        bytes[] memory extensionsData;

        address[] memory voters = new address[](2);
        voters[0] = creator;
        voters[1] = patron;

        uint256[] memory tokens = new uint256[](2);
        tokens[0] = this.getPatronContribution(token, tokenId, patron);
        tokens[1] = tokens[0];

        uint32[16] memory govSettings;
        govSettings = [uint32(300), 0, 20, 52, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];

        uint256 count = this.getBergerCount();
        address payable dao = payable(
            KaliDAOfactory(this.getKaliDaoFactory()).deployKaliDAO(
                string.concat("BergerTime #", LibString.toString(count)),
                string.concat("BT #", LibString.toString(count)),
                " ",
                true,
                extensions,
                extensionsData,
                voters,
                tokens,
                govSettings
            )
        );

        this.setImpactDao(token, tokenId, dao);
        addBergerCount();
        return dao;
    }

    /// @notice Update DAO balance when ImpactToken is purchased.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param patron Patron of ERC721.
    function updateBalances(address token, uint256 tokenId, address patron) internal {
        // Get DAO address to manage revenue from Harberger Tax
        address dao = this.getImpactDao(token, tokenId);

        if (dao == address(0)) {
            // Summon DAO with 50/50 ownership between creator and patron(s).
            summonDao(token, tokenId, this.getCreator(token, tokenId), patron);
        } else {
            // Update DAO balance.
            _balance(token, tokenId, dao);
        }
    }

    /// @notice Rebalance Impact DAO.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param dao ImpactDAO summoned for ERC721.
    function _balance(address token, uint256 tokenId, address dao) private {
        for (uint256 i = 0; i < this.getPatronCount(token, tokenId);) {
            // Retrieve patron and patron contribution.
            address _patron = this.getPatron(token, tokenId, i);
            uint256 contribution = this.getPatronContribution(token, tokenId, _patron);

            // Retrieve KaliDAO balance data.
            uint256 _contribution = IERC20(dao).balanceOf(msg.sender);

            // Retrieve creator.
            address creator = this.getCreator(token, tokenId);

            if (contribution != _contribution) {
                // Determine to mint or burn.
                if (contribution > _contribution) {
                    IKaliTokenManager(dao).mintTokens(creator, contribution - _contribution);
                    IKaliTokenManager(dao).mintTokens(_patron, contribution - _contribution);
                } else if (contribution < _contribution) {
                    IKaliTokenManager(dao).burnTokens(creator, _contribution - contribution);
                    IKaliTokenManager(dao).burnTokens(_patron, _contribution - contribution);
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// Unclaimed Logic
    /// -----------------------------------------------------------------------

    function claim() external payable {
        uint256 amount = this.getUnclaimed(msg.sender);
        if (amount == 0) revert InvalidClaim();

        deleteUnclaimed(msg.sender);

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /// -----------------------------------------------------------------------
    /// Patron Logic
    /// -----------------------------------------------------------------------

    /// @notice Buy ERC721 NFT.
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
        transferNft(token, tokenId, owner, msg.sender, newPrice);

        // Balance DAO according to updated contribution.
        updateBalances(token, tokenId, msg.sender);
    }

    /// @notice Set new price for purchase.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param price New purchase price for ERC721.
    function setPrice(address token, uint256 tokenId, uint256 price)
        external
        payable
        onlyPatron(token, tokenId)
        collectPatronage(token, tokenId)
    {
        if (price == 0) revert InvalidPrice();
        this.setUint(keccak256(abi.encode(token, tokenId, ".price")), price);
    }

    /// @notice To make deposit.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param deposit Amount to deposit to pay for tax.
    function addDeposit(address token, uint256 tokenId, uint256 deposit) external payable onlyPatron(token, tokenId) {
        this.addUint(keccak256(abi.encode(token, tokenId, ".deposit")), deposit);
    }

    /// @notice Withdraw from deposit.
    /// @param token ERC721 token address.
    /// @param tokenId ERC721 tokenId.
    /// @param amount Amount to withdraw from deposit.
    function exit(address token, uint256 tokenId, uint256 amount)
        public
        collectPatronage(token, tokenId)
        onlyPatron(token, tokenId)
    {
        uint256 deposit = this.getDeposit(token, tokenId);
        if (deposit >= amount) revert InvalidExit();

        (bool success,) = msg.sender.call{value: deposit - amount}("");
        if (!success) revert TransferFailed();

        _forecloseIfNecessary(token, tokenId, deposit);
    }

    /// -----------------------------------------------------------------------
    /// Setter Logic
    /// -----------------------------------------------------------------------

    function setKaliDaoFactory(address factory) external payable onlyOperator {
        this.setAddress(keccak256(abi.encodePacked("dao.factory")), factory);
    }

    function setImpactDao(address token, uint256 tokenId, address impactDao) external payable onlyOperator {
        this.setAddress(keccak256(abi.encode(token, tokenId, ".impactDao")), impactDao);
    }

    function setTax(address token, uint256 tokenId, uint256 _tax) external payable onlyOperator {
        this.setUint(keccak256(abi.encode(token, tokenId, ".tax")), _tax);
    }

    function setCreator(address token, uint256 tokenId, address creator) external payable onlyOperator {
        this.setAddress(keccak256(abi.encode(token, tokenId, ".creator")), creator);
    }

    function setTokenDetail(address token, uint256 tokenId, string calldata detail) internal {
        this.setString(keccak256(abi.encode(token, tokenId, ".detail")), detail);
    }

    function setTokenPurchaseStatus(address token, uint256 tokenId, bool _forSale) internal {
        this.setBool(keccak256(abi.encode(token, tokenId, ".forSale")), _forSale);
    }

    function _setPrice(address token, uint256 tokenId, uint256 price) internal {
        this.setUint(keccak256(abi.encode(token, tokenId, ".price")), price);
    }

    function _addDeposit(address token, uint256 tokenId, uint256 deposit) internal {
        this.addUint(keccak256(abi.encode(token, tokenId, ".deposit")), deposit);
    }

    function setTimeLastCollected(address token, uint256 tokenId, uint256 timestamp) internal {
        this.setUint(keccak256(abi.encode(token, tokenId, ".timeLastCollected")), timestamp);
    }

    function setTimeAcquired(address token, uint256 tokenId, uint256 timestamp) internal {
        this.setUint(keccak256(abi.encode(token, tokenId, ".timeAcquired")), timestamp);
    }

    function setOwner(address token, uint256 tokenId, address owner) internal {
        this.setAddress(keccak256(abi.encode(token, tokenId, ".owner")), owner);
    }

    function setPatron(address token, uint256 tokenId, address patron) internal {
        incrementPatronId(token, tokenId);
        this.setAddress(keccak256(abi.encode(token, tokenId, this.getPatronCount(token, tokenId))), patron);
    }

    function setPatronStatus(address token, uint256 tokenId, address patron, bool status) internal {
        this.setBool(keccak256(abi.encode(token, tokenId, patron, ".isPatron")), status);
    }

    /// -----------------------------------------------------------------------
    /// Getter Logic
    /// -----------------------------------------------------------------------

    function getKaliDaoFactory() external view returns (address) {
        return this.getAddress(keccak256(abi.encodePacked("dao.factory")));
    }

    function getBergerCount() external view returns (uint256) {
        return this.getUint(keccak256(abi.encodePacked("bergerTimes.count")));
    }

    function getImpactDao(address token, uint256 tokenId) external view returns (address) {
        return this.getAddress(keccak256(abi.encode(token, tokenId, ".impactDao")));
    }

    function getTokenStatus(address token, uint256 tokenId) external view returns (bool) {
        return this.getBool(keccak256(abi.encode(token, tokenId, ".forSale")));
    }

    function getTax(address token, uint256 tokenId) external view returns (uint256 _tax) {
        _tax = this.getUint(keccak256(abi.encode(token, tokenId, ".tax")));
        return (_tax == 0) ? _tax = 50 : _tax; // default tax rate is hardcoded to 50%
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
        return this.getUint(keccak256(abi.encode(token, tokenId, ".patronCount")));
    }

    function getPatronId(address token, uint256 tokenId, address patron) external view returns (uint256) {
        uint256 count = this.getPatronCount(token, tokenId);

        for (uint256 i = 0; i < count;) {
            if (patron == this.getPatron(token, tokenId, i)) return i;
            unchecked {
                ++i;
            }
        }

        return 0;
    }

    function isPatron(address token, uint256 tokenId, address patron) external view returns (bool) {
        return this.getBool(keccak256(abi.encode(token, tokenId, patron, ".isPatron")));
    }

    function getPatron(address token, uint256 tokenId, uint256 patronId) external view returns (address) {
        return this.getAddress(keccak256(abi.encode(token, tokenId, patronId)));
    }

    function getPatronContribution(address token, uint256 tokenId, address patron) external view returns (uint256) {
        return this.getUint(keccak256(abi.encode(token, tokenId, patron)));
    }

    /// -----------------------------------------------------------------------
    /// Add Logic
    /// -----------------------------------------------------------------------

    function addBergerCount() internal {
        this.addUint(keccak256(abi.encodePacked("bergerTimes.count")), 1);
    }

    function addUnclaimed(address user, uint256 amount) internal {
        this.addUint(keccak256(abi.encode(user, ".unclaimed")), amount);
    }

    function addTimeHeld(address user, uint256 time) internal {
        this.addUint(keccak256(abi.encode(user, ".timeHeld")), time);
    }

    function addTotalCollected(address token, uint256 tokenId, uint256 collected) internal {
        this.addUint(keccak256(abi.encode(token, tokenId, ".totalCollected")), collected);
    }

    function incrementPatronId(address token, uint256 tokenId) internal {
        this.addUint(keccak256(abi.encode(token, tokenId, ".patronCount")), 1);
    }

    function addPatronContribution(address token, uint256 tokenId, address patron, uint256 amount) internal {
        this.addUint(keccak256(abi.encode(token, tokenId, patron)), amount);
    }

    /// -----------------------------------------------------------------------
    /// Delete Logic
    /// -----------------------------------------------------------------------

    function deletePrice(address token, uint256 tokenId) internal {
        return this.deleteUint(keccak256(abi.encode(token, tokenId, ".price")));
    }

    function deleteDeposit(address token, uint256 tokenId) internal {
        return this.deleteUint(keccak256(abi.encode(token, tokenId, ".deposit")));
    }

    function deleteUnclaimed(address user) internal {
        this.deleteUint(keccak256(abi.encode(user, ".unclaimed")));
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
    function isForeclosed(address token, uint256 tokenId) external view returns (bool, uint256) {
        // returns whether it is in foreclosed state or not
        // depending on whether deposit covers patronage due
        // useful helper function when price should be zero, but contract doesn't reflect it yet.
        uint256 toCollect = this.patronageToCollect(token, tokenId);
        uint256 _deposit = this.getDeposit(token, tokenId);
        if (toCollect >= _deposit) {
            return (true, 0);
        } else {
            return (false, _deposit - toCollect);
        }
    }

    // credit: simondlr  https://github.com/simondlr/thisartworkisalwaysonsale/blob/master/packages/hardhat/contracts/v1/ArtStewardV2.sol
    function foreclosureTime(address token, uint256 tokenId) external view returns (uint256) {
        uint256 pps = this.getPrice(token, tokenId) / 365 days * (this.getTax(token, tokenId) / 100);
        (, uint256 daw) = this.isForeclosed(token, tokenId);
        if (daw > 0) {
            return block.timestamp + daw / pps;
        } else if (pps > 0) {
            // it is still active, but in foreclosure state
            // it is block.timestamp or was in the pas
            // not active and actively foreclosed (price is zero)
            uint256 timeLastCollected = this.getTimeLastCollected(token, tokenId);
            return timeLastCollected
                + (block.timestamp - timeLastCollected) * this.getDeposit(token, tokenId)
                    / this.patronageToCollect(token, tokenId);
        } else {
            // not active and actively foreclosed (price is zero)
            return this.getTimeLastCollected(token, tokenId); // it has been foreclosed or in foreclosure.
        }
    }

    function _forecloseIfNecessary(address token, uint256 tokenId, uint256 _deposit) internal {
        if (_deposit == 0) {
            IERC721(token).safeTransferFrom(IERC721(token).ownerOf(tokenId), address(this), tokenId);
            deleteDeposit(token, tokenId);
            deletePrice(token, tokenId);
        }
    }

    // credit: simondlr  https://github.com/simondlr/thisartworkisalwaysonsale/blob/master/packages/hardhat/contracts/v1/ArtStewardV2.sol
    function _collectPatronage(address token, uint256 tokenId) internal {
        uint256 price = this.getPrice(token, tokenId);
        uint256 toCollect = this.patronageToCollect(token, tokenId);
        uint256 deposit = this.getDeposit(token, tokenId);

        uint256 timeLastCollected = this.getTimeLastCollected(token, tokenId);

        if (price != 0) {
            // price > 0 == active owned state
            if (toCollect >= deposit) {
                // foreclosure happened in the past
                // up to when was it actually paid for?
                // TLC + (time_elapsed)*deposit/toCollect
                setTimeLastCollected(token, tokenId, (block.timestamp - timeLastCollected) * deposit / toCollect);

                // Add to unclaimed pool for corresponding dao to claim at later time.
                addUnclaimed(this.getImpactDao(token, tokenId), deposit);

                // Take deposit.
                toCollect = deposit;
            } else {
                // Normal collection.
                setTimeLastCollected(token, tokenId, block.timestamp);

                // Add to unclaimed pool for corresponding dao to claim at later time.
                if (toCollect != 0) addUnclaimed(this.getImpactDao(token, tokenId), toCollect);
            }

            // Add to total amount collected.
            addTotalCollected(token, tokenId, toCollect);

            // Add to amount collected by patron.
            addPatronContribution(token, tokenId, msg.sender, toCollect);

            // Foreclose if necessary.
            _forecloseIfNecessary(token, tokenId, deposit - toCollect);
        }
    }

    /// -----------------------------------------------------------------------
    /// NFT Transfer & Payments Logic
    /// -----------------------------------------------------------------------

    /// @notice Internal function to transfer ImpactToken.
    // credit: simondlr  https://github.com/simondlr/thisartworkisalwaysonsale/blob/master/packages/hardhat/contracts/v1/ArtStewardV2.sol
    function transferNft(address token, uint256 tokenId, address currentOwner, address newOwner, uint256 price)
        internal
    {
        // note: it would also tabulate time held in stewardship by smart contract
        addTimeHeld(currentOwner, this.getTimeLastCollected(token, tokenId) - this.getTimeAcquired(token, tokenId));

        // Otherwise transfer ownership.
        IERC721(token).safeTransferFrom(currentOwner, newOwner, tokenId);

        // Update new price.
        _setPrice(token, tokenId, price);

        // Update time of acquisition.
        setTimeAcquired(token, tokenId, block.timestamp);

        // Add new owner as patron
        setPatron(token, tokenId, newOwner);

        // Toggle new owner's patron status
        setPatronStatus(token, tokenId, newOwner, true);
    }

    /// @notice Internal function to pdrocess purchase payment.
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
        if (price != currentPrice || newPrice == 0 || currentPrice > msg.value) revert InvalidPurchase();

        // Add purchase price to patron contribution.
        addPatronContribution(token, tokenId, msg.sender, price);

        // Retrieve deposit, if any.
        uint256 deposit = this.getDeposit(token, tokenId);

        if (price + deposit > 0) {
            // this won't execute if KaliBerger owns it. price = 0. deposit = 0.
            // pay previous owner their price + deposit back.
            if (price + deposit > msg.value) revert InvalidPurchase();
            (bool success,) = currentOwner.call{value: price + deposit}("");
            if (!success) addUnclaimed(currentOwner, price + deposit);
            deleteDeposit(token, tokenId);
        }

        // Make deposit, if any.
        _addDeposit(token, tokenId, msg.value - price);
        // (bool _success,) = address(this).call{value: msg.value - price}("");
        // if (!_success) revert TransferFailed();
    }

    /// @notice Interface for any contract that wants to support safeTransfers from ERC721 asset contracts.
    /// credit: z0r0z.eth https://github.com/kalidao/kali-contracts/blob/main/contracts/utils/NFTreceiver.sol
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4 sig) {
        sig = 0x150b7a02; // 'onERC721Received(address,address,uint256,bytes)'
    }

    receive() external payable virtual {}
}
