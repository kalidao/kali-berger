// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {IERC721} from "lib/forge-std/src/interfaces/IERC721.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {MockERC721} from "lib/solbase/test/utils/mocks/MockERC721.sol";
import {KaliDAOfactory, KaliDAO} from "src/kalidao/KaliDAOfactory.sol";

import {Storage} from "src/Storage.sol";
import {IStorage} from "src/interface/IStorage.sol";
import {KaliBerger} from "src/KaliBerger.sol";
import {IPatronCertificate} from "src/interface/IPatronCertificate.sol";
import {PatronCertificate} from "src/tokens/PatronCertificate.sol";

contract KaliBergerTest is Test {
    MockERC721 token_1;
    MockERC721 token_2;
    MockERC721 token_3;

    KaliDAOfactory factory;
    KaliDAO daoTemplate;

    Storage stor;
    KaliBerger kaliBerger;
    KaliBerger kaliBerger_uninitialized;
    PatronCertificate patronCertificate;

    IStorage iStorage;

    /// @dev Users.
    address payable public alfred = payable(makeAddr("alfred"));
    address payable public bob = payable(makeAddr("bob"));
    address payable public charlie = payable(makeAddr("charlie"));
    address payable public darius = payable(makeAddr("darius"));
    address payable public earn = payable(makeAddr("earn"));
    address payable public dao = payable(makeAddr("dao"));

    /// @dev Helpers.
    string internal constant description = "TEST";
    bytes32 internal constant name1 = 0x5445535400000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant name2 = 0x5445535432000000000000000000000000000000000000000000000000000000;

    /// @dev KaliDAO init params
    address[] extensions;
    bytes[] extensionsData;
    address[] voters = [address(alfred)];
    uint256[] tokens = [10];
    uint32[16] govSettings = [uint32(300), 0, 20, 52, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];

    /// -----------------------------------------------------------------------
    /// Contracts Setup
    /// -----------------------------------------------------------------------

    /// @notice Set up the testing suite.
    function setUp() public payable {
        // Deploy a KaliDAO factory
        daoTemplate = new KaliDAO();
        factory = new KaliDAOfactory(payable(daoTemplate));
        factory.deployKaliDAO(
            "Berger Council", "BC", " ", true, extensions, extensionsData, voters, tokens, govSettings
        );

        // Deploy and initialize KaliBerger contract.
        kaliBerger = new KaliBerger();
        kaliBerger_uninitialized = new KaliBerger();

        // Deploy and initialize PatronCertificate contract.
        patronCertificate = new PatronCertificate(address(kaliBerger));

        // Deploy 3 ERC721 tokens.
        token_1 = deployErc721();
        token_2 = deployErc721();
        token_3 = deployErc721();

        // Mint Alfred an ERC721.
        mintErc721(token_1, 1, alfred);

        // Mint Bob an ERC721.
        mintErc721(token_2, 1, bob);

        // Mint Charlie an ERC721.
        mintErc721(token_3, 1, charlie);

        vm.warp(block.timestamp + 1000);
    }

    /// -----------------------------------------------------------------------
    /// Initialization Test
    /// -----------------------------------------------------------------------

    /// @notice Initialize KaliBerger.
    function testInitialized() public payable {
        initialize(dao, address(factory), address(patronCertificate));
        assertEq(kaliBerger.getKaliDaoFactory(), address(factory));
        assertEq(kaliBerger.getCertificateMinter(), address(patronCertificate));
    }

    /// @notice Update KaliDAO factory.
    function testFactory() public payable {
        initialize(dao, address(factory), address(patronCertificate));

        vm.prank(dao);
        kaliBerger.setKaliDaoFactory(earn);
        assertEq(kaliBerger.getKaliDaoFactory(), address(earn));
    }

    /// @notice Update KaliDAO factory.
    function testFactory_NotInitialized() public payable {
        vm.expectRevert(KaliBerger.NotInitialized.selector);
        vm.prank(dao);
        kaliBerger.setKaliDaoFactory(earn);
    }

    /// @notice Update Patron Certificate.
    function testMinter() public payable {
        initialize(dao, address(factory), address(patronCertificate));

        vm.prank(dao);
        kaliBerger.setCertificateMinter(earn);
        assertEq(kaliBerger.getCertificateMinter(), address(earn));
    }

    /// @notice Update Patron Certificate.
    function testMinter_NotInitialized() public payable {
        vm.expectRevert(KaliBerger.NotInitialized.selector);
        vm.prank(dao);
        kaliBerger.setCertificateMinter(earn);
    }

    /// @notice With KaliBerger uninitialized, Bob tries to buy tokens and gets an NotInitialized() error.
    function testNotInitialized() public payable {
        // Deal Bob ether
        vm.deal(bob, 10 ether);

        // Bob buys
        vm.expectRevert(KaliBerger.NotInitialized.selector);
        vm.prank(bob);
        kaliBerger.buy{value: 0.1 ether}(address(token_3), 1, 1 ether, 0);
    } // timestamp: 1500

    /// -----------------------------------------------------------------------
    /// Escrow & Approve Test
    /// -----------------------------------------------------------------------

    /// @notice The Gang escrows their tokens.
    function testEscrow() public payable {
        initialize(dao, address(factory), address(patronCertificate));

        escrow(alfred, token_1, 1);
        escrow(bob, token_2, 1);
        escrow(charlie, token_3, 1);
    } // 300

    /// @notice DAO approves all tokens for purchase and adds custom detail.
    function testApprove() public payable {
        // Escrow.
        testEscrow(); // 300

        // DAO approves.
        vm.warp(500);
        approve(token_1, 1, "Alfred NFT"); // 500x

        // DAO approves.
        vm.warp(1000);
        approve(token_2, 1, "Bob NFT"); // 1000

        // DAO approves.
        vm.warp(2000);
        approve(token_3, 1, "Charlie NFT"); // 2000
    } // 500, 1000, 2000

    /// @notice Validate patronage after Approve
    function testApprove_PatronageToCollect() public payable {
        uint256 timestamp = 10000000;
        uint256 tokenId = 1;

        testApprove();
        vm.warp(timestamp);

        // Validate
        validatePatronageToCollect(token_1, tokenId);
        validatePatronageToCollect(token_2, tokenId);
        validatePatronageToCollect(token_3, tokenId);
    } // timestamp: 10000000

    /// @notice Calculate patronage to collect after Approve
    function testApprove_NotForSale() public payable {
        // Escrow
        testEscrow();

        // DAO disapproves
        vm.prank(dao);
        kaliBerger.approve(address(token_1), 1, false, "Cool NFT!");
        vm.warp(500);

        // Validate
        assertEq(token_1.balanceOf(alfred), 1);
        assertEq(token_1.balanceOf(address(kaliBerger)), 0);
        assertEq(kaliBerger.getTokenPurchaseStatus(address(token_1), 1), false);
    } // timestamp: 500

    /// -----------------------------------------------------------------------
    /// Token Detail Test
    /// -----------------------------------------------------------------------

    /// @notice Update token detail.
    function testSetTokenDetail() public payable {
        testApprove();

        vm.prank(dao);
        kaliBerger.setTokenDetail(address(token_1), 1, "Charlie's NFT");
        assertEq(kaliBerger.getTokenDetail(address(token_1), 1), "Charlie's NFT");
    }

    function testSetTokenDetail_NotInitialized() public payable {
        testEscrow();

        vm.expectRevert(KaliBerger.NotInitialized.selector);
        vm.prank(dao);
        kaliBerger.setTokenDetail(address(token_1), 1, "Cool!");
    }

    /// -----------------------------------------------------------------------
    /// Buy Test - Single Token
    /// -----------------------------------------------------------------------

    // TODO: Tests for getTimeHeld(), getPatronId(), isPatron()

    /// @notice Bob buys token_1, tokenId #1 and declares a new price for sale
    function testSingleBuy() public payable {
        // Escrow & approve
        testApprove();

        // Bob buys.
        primaryBuy(bob, address(token_1), 1, 1 ether, alfred);
    }

    /// @notice Unsatisfied with the first price, Bob sets a new price.
    function testSingleBuy_setPrice() public payable {
        // Bob buys.
        testSingleBuy();

        // Bob sets new price.
        setPrice(bob, address(token_1), 1, 2 ether, alfred);
    } // timestamp: 5000

    /// @notice Bob add deposits to maintain his ownership of token_1, token #1 for a longer period of time.
    function testSingleBuy_addDeposit() public payable {
        // Bob buys.
        testSingleBuy();

        // Bob adds more ether as deposit.
        addDeposit(bob, address(token_1), 1, 0.5 ether, alfred);
    }

    /// @notice DAO changes tax.
    function testSingleBuy_setTax() public payable {
        // Bob buys.
        testSingleBuy();

        // Bob sets new tax.
        setTax(address(token_1), 1, 30, alfred);
    }

    /// @notice Charlie and Darius add deposits to help Bob maintain ownership of token_1, token #1 for a longer period of time.
    function testSingleBuy_addDeposit_byOthers() public payable {
        // Bob buys.
        testSingleBuy();

        // Deal Charlie and Darius ether.
        vm.deal(charlie, 10 ether);
        vm.deal(darius, 10 ether);

        // Charlie adds deposit.
        addDeposit(charlie, address(token_1), 1, 0.5 ether, alfred);

        // Darius adds deposit.
        addDeposit(darius, address(token_1), 1, 0.5 ether, alfred);
    }

    /// @notice Bob exits a portion of his previous deposit.
    function testSingleBuy_exit() public payable {
        // Bob buys and makes deposit.
        testSingleBuy_addDeposit();

        // Bob exits a portion fo deposit.
        exit(bob, address(token_1), 1, 0.1 ether, alfred);
    }

    /// @notice Bob ragequits by removing all of his deposit, triggering foreclosure.
    function testSingleBuy_ragequit() public payable {
        testSingleBuy_addDeposit();

        // Retrieve data for validation.
        uint256 patronage = kaliBerger.patronageToCollect(address(token_1), 1);
        uint256 deposit = kaliBerger.getDeposit(address(token_1), 1);

        // Bob withdraws all of deposit.
        exit(bob, address(token_1), 1, deposit - patronage, alfred);
    }

    /// @notice Charlie buys token_1, tokenId #1 and declares new price for sale.
    function testSingleBuy_secondBuy() public payable {
        // Bob buys.
        testSingleBuy();

        // Charlie buys.
        secondaryBuy(charlie, address(token_1), 1, 1.5 ether, alfred);
    }

    /// @notice After the initial purchase by Bob centuries ago, Charlie came along in year 2055 to purchase the now foreclosed token_1, #1.
    function testSingleBuy_foreclosedSecondBuy() public payable {
        // Bob buys.
        testSingleBuy();
        vm.warp(2707346409);

        // Bob defaults. Charlie buys.
        secondaryForeclosedBuy(charlie, address(token_1), 1, 3 ether, alfred);
    }

    /// @notice Earn buys token_1, tokenId #1 and declares new price for sale.
    function testSingleBuy_thirdBuy() public payable {
        // Bob and Charlie buy.
        testSingleBuy_secondBuy();

        // Earn buys.
        secondaryBuy(earn, address(token_1), 1, 5 ether, alfred);
    }

    /// @notice Alfred withdraws token_1, tokenId #1.
    function testSingleBuy_pull() public payable {
        // Continuing from third buy by Earn.
        testSingleBuy_thirdBuy();
        vm.warp(2707346409);

        // Alfred pulls ERC721.
        pull(alfred, address(token_1), 1);
    }

    /// @notice .
    function testBalance_DefectedCreator() public payable {
        // Bob buys.
        testSingleBuy();

        // Mint KaliDAO tokens.
        address payable impactDao = payable(kaliBerger.getImpactDao(address(token_1), 1));
        mintImpactDaoTokens(KaliDAO(impactDao), alfred, alfred, 100 ether);

        // Balance.
        emit log_uint(block.timestamp);
        balanceDao(block.timestamp + 20000, address(token_1), 1, alfred);
    }

    /// @notice .
    function testBalance_DefectedPatron() public payable {
        // Bob buys.
        testSingleBuy();

        // Mint KaliDAO tokens.
        address payable impactDao = payable(kaliBerger.getImpactDao(address(token_1), 1));
        mintImpactDaoTokens(KaliDAO(impactDao), alfred, bob, 100 ether);

        // Balance.
        emit log_uint(block.timestamp);
        balanceDao(block.timestamp + 20000, address(token_1), 1, alfred);
    }

    /// -----------------------------------------------------------------------
    /// Buy Test - Multiple Tokens
    /// -----------------------------------------------------------------------

    /// @notice Darius buys all tokens and declares new prices for each
    function testMultipleBuy() public payable {
        // Escrow & approve
        testApprove();

        // Darius buys.
        primaryBuy(darius, address(token_1), 1, 1 ether, alfred);
        primaryBuy(darius, address(token_2), 1, 1 ether, bob);
        primaryBuy(darius, address(token_3), 1, 1 ether, charlie);
    }

    /// -----------------------------------------------------------------------
    /// Custom Error Test
    /// -----------------------------------------------------------------------

    /// @notice Charlie tries to escrows tokenId #1 of token_1 and triggers NotAuthorized() error.
    function testEscrow_byOthers() public payable {
        // Approve KaliBerger to transfer ERC721
        vm.prank(alfred);
        token_1.approve(address(kaliBerger), 1);
        vm.warp(200);

        // Charlie escrows Alfred's NFT
        vm.expectRevert(KaliBerger.NotAuthorized.selector);
        vm.prank(charlie);
        kaliBerger.escrow(address(token_1), 1, charlie);
    }

    /// @notice Charlie tries to set a new price and gets an NotAuthorized() error.
    function testSingleBuy_setPrice_byOthers() public payable {
        // Bob buys.
        testSingleBuy();

        // Charlie tries to set new price on behalf of Alfred.
        vm.expectRevert(KaliBerger.NotAuthorized.selector);
        vm.prank(charlie);
        kaliBerger.setPrice(address(token_1), 1, 2 ether);
    }

    /// @notice Bob withdraws too much and triggers InvalidExit() error.
    function testSingleBuy_exit_invalidExit() public payable {
        // Add deposit.
        testSingleBuy_addDeposit();

        // InvalidExit()
        vm.expectRevert(KaliBerger.InvalidExit.selector);
        vm.prank(bob);
        kaliBerger.exit(address(token_1), 1, 1 ether);
    }

    /// @notice Charlie tries to withdraw from deposit and triggers NotAuthorized() error.
    function testSingleBuy_exit_byOthers() public payable {
        // Add deposit.
        testSingleBuy_addDeposit();

        // InvalidExit()
        vm.expectRevert(KaliBerger.NotAuthorized.selector);
        vm.prank(charlie);
        kaliBerger.exit(address(token_1), 1, 0.2 ether);
    }

    /// @notice Alfred tries to withdraw token_1, tokenId #1 but cannot bc it has not
    ///         foreclosed yet.
    function testSingleBuy_pull_invalidExit() public payable {
        // Continuing from third buy by Earn.
        testSingleBuy_secondBuy();

        // InvalidExit()
        vm.expectRevert(KaliBerger.InvalidExit.selector);
        vm.prank(alfred);
        kaliBerger.pull(address(token_1), 1);

        // Validate
        assertEq(token_1.balanceOf(alfred), 0);
        assertEq(token_1.balanceOf(address(kaliBerger)), 1);
    }

    /// @notice Earn tries to withdraw token_1, tokenId #1 on behalf of Alfred,
    /// @notice but triggers NotAuthorized() error because Alfred is the creator of NFT.
    function testSingleBuy_pull_notAuthorized() public payable {
        // Continuing from third buy by Earn.
        testSingleBuy_thirdBuy();
        vm.warp(block.timestamp + 10000000);

        // Earn withdraws but errors out.
        vm.expectRevert(KaliBerger.NotAuthorized.selector);
        vm.prank(earn);
        kaliBerger.pull(address(token_1), 1);

        // Validate.
        assertEq(token_1.balanceOf(alfred), 0);
        assertEq(token_1.balanceOf(earn), 0);
        assertEq(token_1.balanceOf(address(kaliBerger)), 1);
        balanceDao(block.timestamp + 10000, address(token_1), 1, alfred);
    }

    function testReceiveETH() public payable {
        (bool sent,) = address(kaliBerger).call{value: 5 ether}("");
        assert(sent);
        assert(address(kaliBerger).balance == 5 ether);
    }

    /// -----------------------------------------------------------------------
    /// Helper Logic
    /// -----------------------------------------------------------------------

    /// @notice Deploy ERC721.
    function deployErc721() internal returns (MockERC721 token) {
        token = new MockERC721("TEST", "TEST");
    }

    /// @notice Mint ERC721.
    function mintErc721(MockERC721 token, uint256 tokenId, address recipient) internal {
        if (address(token) == address(0)) {
            token = deployErc721();
        }

        // Mint recipient an ERC721
        token.mint(recipient, tokenId);
        assertEq(token.balanceOf(recipient), tokenId);
    }

    /// @notice Initialize KaliBerger.
    function initialize(address _dao, address _factory, address minter) internal {
        kaliBerger.initialize(_dao, _factory, minter);
    }

    /// @notice Escrow ERC721.
    function escrow(address user, MockERC721 token, uint256 tokenId) internal {
        // Approve KaliBerger to transfer ERC721
        vm.prank(user);
        token.approve(address(kaliBerger), tokenId);
        vm.warp(200);

        // User escrows ERC721 with KaliBerger
        vm.prank(user);
        kaliBerger.escrow(address(token), tokenId, user);
        vm.warp(300);

        // Validate
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(kaliBerger)), tokenId);
    } // 300

    /// @notice Approve ERC721 for purchase.
    function approve(MockERC721 token, uint256 tokenId, string memory detail) public payable {
        // DAO approves ERC721 for sale
        vm.prank(dao);
        kaliBerger.approve(address(token), tokenId, true, detail);

        // Validate
        assertEq(kaliBerger.getTokenPurchaseStatus(address(token), tokenId), true);
        assertEq(kaliBerger.getTokenDetail(address(token), tokenId), detail);
        assertEq(kaliBerger.getOwner(address(token), tokenId), address(kaliBerger));
    }

    /// @notice Validate amount of patronage to collect.
    function validatePatronageToCollect(MockERC721 token, uint256 tokenId) public payable {
        uint256 amount = kaliBerger.getPrice(address(token), tokenId)
            * (block.timestamp - kaliBerger.getTimeLastCollected(address(token), tokenId))
            * kaliBerger.getTax(address(token), tokenId) / 365 days / 100;
        assertEq(kaliBerger.patronageToCollect(address(token), tokenId), amount);
        // emit log_uint(amount);
    }

    /// @notice Rebalance DAO tokens.
    function balanceDao(uint256 timestamp, address token, uint256 tokenId, address creator) public payable {
        // Validate
        vm.warp(timestamp);

        // Darius balances a DAO for everyone.
        vm.prank(darius);
        kaliBerger.balanceDao(token, tokenId);

        vm.warp(timestamp + 1000);
        // Retrieve token balances to validate DAO is in balance.
        address impactDao = kaliBerger.getImpactDao(token, tokenId);
        uint256 creator_balance = IERC20(impactDao).balanceOf(creator);
        uint256 alfred_balance = IERC20(impactDao).balanceOf(alfred);
        uint256 bob_balance = IERC20(impactDao).balanceOf(bob);
        uint256 charlie_balance = IERC20(impactDao).balanceOf(charlie);
        uint256 darius_balance = IERC20(impactDao).balanceOf(darius);
        uint256 earn_balance = IERC20(impactDao).balanceOf(earn);

        // Validate
        if (creator == alfred) assertEq(creator_balance, bob_balance + charlie_balance + earn_balance + darius_balance);
        if (creator == bob) assertEq(creator_balance, alfred_balance + charlie_balance + earn_balance + darius_balance);
        if (creator == charlie) assertEq(creator_balance, alfred_balance + bob_balance + earn_balance + darius_balance);
        emit log_uint(alfred_balance);
        emit log_uint(bob_balance);
        emit log_uint(charlie_balance);
        emit log_uint(darius_balance);
        emit log_uint(earn_balance);
    }

    /// @notice Buy ERC721.
    function primaryBuy(address buyer, address token, uint256 tokenId, uint256 newPrice, address creator)
        public
        payable
    {
        vm.warp(block.timestamp + 1000);

        // Deal buyer ether if buyer does not have any ether.
        if (address(buyer).balance < 0.01 ether) vm.deal(buyer, 10 ether);

        // Get berger count before purchase.
        uint256 count = kaliBerger.getBergerCount();

        // Buyer buys.
        vm.prank(buyer);
        kaliBerger.buy{value: 0.1 ether}(token, tokenId, newPrice, 0);

        // Validate summoning of ImpactDAO.
        assertEq(kaliBerger.getBergerCount(), count == 0 ? 1 : ++count);

        // Validate ownership of Patron Certificate for token_1, #1.
        assertEq(
            IPatronCertificate(address(patronCertificate)).ownerOf(
                IPatronCertificate(address(patronCertificate)).getTokenId(address(token), tokenId)
            ),
            buyer
        );

        // Balance DAO.
        balanceDao(block.timestamp + 1000, address(token), tokenId, creator);
    }

    /// @notice Buy ERC721.
    function secondaryBuy(address buyer, address token, uint256 tokenId, uint256 newPrice, address creator)
        public
        payable
    {
        vm.warp(block.timestamp + 1000);

        // Deal buyer ether if buyer does not have any ether.
        if (address(buyer).balance < 0.01 ether) vm.deal(buyer, 10 ether);

        // Retrieve data for validation.
        address impactDao = kaliBerger.getImpactDao(address(token), tokenId);
        uint256 patronage = kaliBerger.patronageToCollect(address(token), tokenId);
        uint256 oldImpactDaoBalance = address(impactDao).balance + kaliBerger.getUnclaimed(impactDao); // Consider a function to aggregate all impactDao balances

        // Get current price and add slightly more as deposit.
        uint256 currentPrice = kaliBerger.getPrice(token, tokenId);

        // Buyer buys.
        vm.prank(buyer);
        kaliBerger.buy{value: currentPrice + 0.1 ether}(token, tokenId, newPrice, currentPrice);

        // ImpactDAO claims.
        claim(impactDao);

        // Validate contract balances.
        assertEq(kaliBerger.getBergerCount(), 1);

        // Validate number of ImpactDAOs.
        assertEq(address(impactDao).balance, oldImpactDaoBalance + patronage);

        // Validate ownership of Patron Certificate for token_1, #1.
        assertEq(
            IPatronCertificate(address(patronCertificate)).ownerOf(
                IPatronCertificate(address(patronCertificate)).getTokenId(address(token), tokenId)
            ),
            buyer
        );

        // Balance DAO.
        balanceDao(block.timestamp + 1000, address(token), tokenId, creator);
    }

    /// @notice Buy ERC721 when it is foreclosed. This is different from secondaryBuy() in that we will use 0 for currentPrice to denote foreclosure status.
    function secondaryForeclosedBuy(address buyer, address token, uint256 tokenId, uint256 newPrice, address creator)
        public
        payable
    {
        vm.warp(block.timestamp + 1000);

        // Deal buyer ether if buyer does not have any ether.
        if (address(buyer).balance < 0.01 ether) vm.deal(buyer, 10 ether);

        // Buyer buys.
        vm.prank(buyer);
        kaliBerger.buy{value: 0.1 ether}(token, tokenId, newPrice, 0);

        // Validate number of ImpactDAOs.
        assertEq(kaliBerger.getBergerCount(), 1);

        // Validate ownership of Patron Certificate for token_1, #1.
        assertEq(
            IPatronCertificate(address(patronCertificate)).ownerOf(
                IPatronCertificate(address(patronCertificate)).getTokenId(address(token), tokenId)
            ),
            buyer
        );

        // ImpactDAO claims.
        address impactDao = kaliBerger.getImpactDao(address(token), tokenId);
        claim(impactDao);

        // emit log_uint(address(impactDao).balance);
        // emit log_uint(address(kaliBerger).balance);
        // emit log_uint(unclaimed);
        // emit log_uint(oldKaliBergerBalance);

        // Balance DAO.
        balanceDao(block.timestamp + 1000, address(token), tokenId, creator);
    }

    /// @notice Set price.
    function setPrice(address user, address token, uint256 tokenId, uint256 newPrice, address creator) public payable {
        // Retrieve data for validation.
        address impactDao = kaliBerger.getImpactDao(address(token), tokenId);
        uint256 patronage = kaliBerger.patronageToCollect(address(token), tokenId);
        uint256 oldImpactDaoBalance = address(impactDao).balance + kaliBerger.getUnclaimed(impactDao); // Consider a function to aggregate all impactDao balances

        // User sets new price.
        vm.prank(user);
        kaliBerger.setPrice(address(token), tokenId, newPrice);

        // ImpactDAO claims.
        claim(impactDao);

        // Validate setting of new price.
        assertEq(kaliBerger.getPrice(address(token), tokenId), newPrice);

        // Validate impactDAO balance.
        assertEq(address(impactDao).balance, oldImpactDaoBalance + patronage);

        // Balance DAO.
        balanceDao(block.timestamp + 1000, address(token), tokenId, creator);
    }

    /// @notice Add deposit.
    function addDeposit(address user, address token, uint256 tokenId, uint256 amount, address creator) public payable {
        // Retrieve data for validation.
        address impactDao = kaliBerger.getImpactDao(address(token), tokenId);
        uint256 deposit = kaliBerger.getDeposit(address(token), tokenId);
        uint256 patronage = kaliBerger.patronageToCollect(address(token), tokenId);
        uint256 oldImpactDaoBalance = address(impactDao).balance + kaliBerger.getUnclaimed(impactDao); // Consider a function to aggregate all impactDao balances

        // User adds deposit.
        vm.prank(user);
        kaliBerger.addDeposit{value: amount}(address(token), tokenId, amount);

        // ImpactDAO claims.
        claim(impactDao);

        // Validate balance and deposit amount.
        assertEq(kaliBerger.getDeposit(address(token), tokenId), deposit + amount - patronage);
        assertEq(address(impactDao).balance, oldImpactDaoBalance + patronage);

        // Balance DAO.
        balanceDao(block.timestamp + 1000, address(token), tokenId, creator);
    }

    /// @notice Set tax.
    function setTax(address token, uint256 tokenId, uint256 tax, address creator) public payable {
        // Set new tax rate.
        vm.prank(dao);
        kaliBerger.setTax(token, tokenId, tax);

        // Validate patron balances.
        balanceDao(block.timestamp + 1000, token, tokenId, alfred);

        // Validate tax update.
        assertEq(kaliBerger.getTax(token, tokenId), tax);

        // Balance DAO.
        balanceDao(block.timestamp + 1000, address(token), tokenId, creator);
    }

    /// @notice Exit.
    function exit(address user, address token, uint256 tokenId, uint256 amount, address creator) public payable {
        // Retrieve data for validation.
        address impactDao = kaliBerger.getImpactDao(address(token), tokenId);
        uint256 depositBeforeExit = kaliBerger.getDeposit(address(token), tokenId);
        uint256 patronage = kaliBerger.patronageToCollect(address(token), tokenId);
        uint256 oldImpactDaoBalance = address(impactDao).balance + kaliBerger.getUnclaimed(impactDao); // Consider a function to aggregate all impactDao balances

        // User withdraws from deposit.
        vm.prank(user);
        kaliBerger.exit(address(token), tokenId, amount);

        // Validate patronage amount.
        assertEq(kaliBerger.getDeposit(address(token), tokenId), depositBeforeExit - amount - patronage);
        assertEq(IERC721(token).balanceOf(address(kaliBerger)), 1);

        // ImpactDAO claims.
        claim(impactDao);
        assertEq(address(impactDao).balance, oldImpactDaoBalance + patronage);

        // Balance DAO.
        balanceDao(block.timestamp + 1000, address(token), tokenId, creator);
    }

    function pull(address user, address token, uint256 tokenId) public payable {
        // User pulls ERC721 out of KaliBerger contract.
        vm.prank(user);
        kaliBerger.pull(token, tokenId);

        // Validate.
        assertEq(MockERC721(token).balanceOf(user), 1);
        assertEq(MockERC721(token).balanceOf(address(kaliBerger)), 0);
        assertEq(kaliBerger.getPrice(address(token), tokenId), 0);
        assertEq(kaliBerger.getDeposit(address(token), tokenId), 0);
        assertEq(kaliBerger.getTokenPurchaseStatus(address(token), tokenId), false);
    }

    function claim(address user) public payable {
        // Retrieve data for validation.
        uint256 bergerBalanceBeforeClaim = address(kaliBerger).balance;
        uint256 userBalanceBeforeClaim = address(user).balance;
        uint256 unclaimed = kaliBerger.getUnclaimed(user);

        // Claim any unclaimed.
        vm.prank(user);
        kaliBerger.claim();

        // Validate balance and deposit amount.
        assertEq(address(user).balance, userBalanceBeforeClaim + unclaimed);
        assertEq(address(kaliBerger).balance, bergerBalanceBeforeClaim - unclaimed);
    }

    function mintImpactDaoTokens(KaliDAO impactDao, address proposer, address recipient, uint256 amount)
        public
        payable
    {
        // Set up voting params.
        address[] memory recipients = new address[](1);
        recipients[0] = recipient;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        bytes[] memory payloads = new bytes[](1);
        payloads[0] = "";

        // Retrieve data for validation.
        uint256 userBalanceBeforeMint = KaliDAO(impactDao).balanceOf(recipient);

        vm.prank(proposer);
        impactDao.propose(KaliDAO.ProposalType.MINT, "", recipients, amounts, payloads);

        vm.warp(block.timestamp + 1000);
        uint256 proposalId = impactDao.proposalCount();

        vm.prank(proposer);
        impactDao.vote(proposalId, true);

        vm.warp(block.timestamp + 100000);

        vm.prank(proposer);
        impactDao.processProposal(proposalId);

        assertEq(KaliDAO(impactDao).balanceOf(recipient), userBalanceBeforeMint + amount);
    }
}
