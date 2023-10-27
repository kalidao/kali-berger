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
    uint256[] shares = [10];
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
            "Berger Council", "BC", " ", true, extensions, extensionsData, voters, shares, govSettings
        );

        // Deploy and initialize KaliBerger contract.
        kaliBerger = new KaliBerger();
        kaliBerger_uninitialized = new KaliBerger();

        // Initialize.
        vm.prank(dao);
        kaliBerger.initialize(dao, address(factory), address(patronCertificate));

        // Deploy and initialize PatronCertificate contract.
        patronCertificate = new PatronCertificate(address(kaliBerger));
        vm.prank(dao);
        kaliBerger.setCertificateMinter(address(patronCertificate));

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

        vm.warp(100);
    } // 100

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
        // emit log_uint(earn_balance);
    }

    /// @notice Buy ERC721.
    function buy(address buyer, address token, uint256 tokenId, uint256 newPrice, address creator) public payable {
        // Escrow & approve
        testApprove();
        vm.warp(block.timestamp + 1000);

        // Deal Bob ether
        if (address(buyer).balance < 0.01 ether) vm.deal(buyer, 10 ether);

        // Get berger count before purchase.
        uint256 count = kaliBerger.getBergerCount();

        // Bob buys
        vm.prank(buyer);
        kaliBerger.buy{value: 0.1 ether}(token, tokenId, newPrice, 0);
        vm.warp(block.timestamp + 1000);

        // Validate balances.
        assertEq(address(kaliBerger).balance, 0.1 ether);
        assertEq(address(buyer).balance, 9.9 ether);

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
        balanceDao(4000, address(token_1), 1, creator);
    }

    /// -----------------------------------------------------------------------
    /// Test Escrow & Approve Logic
    /// -----------------------------------------------------------------------

    /// @notice The Gang escrows their tokens.
    function testEscrow() public payable {
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
    /// Test Buy Logic - Single Token
    /// -----------------------------------------------------------------------

    /// @notice Bob buys token_1, tokenId #1 and declares a new price for sale
    function testSingleBuy() public payable {
        buy(bob, address(token_1), 1, 1 ether, alfred);
    }

    /// @notice Unsatisfied with the first price, Bob sets a new price.
    function testSingleBuy_setPrice() public payable {
        // Bob buys.
        testSingleBuy();
        vm.warp(block.timestamp + 1000);

        // Retrieve data for validation.
        address impactDao = kaliBerger.getImpactDao(address(token_1), 1);
        uint256 oldBalance = address(kaliBerger).balance;
        uint256 patronage = kaliBerger.patronageToCollect(address(token_1), 1);
        uint256 oldImpactDaoBalance = address(impactDao).balance + kaliBerger.getUnclaimed(impactDao); // Consider a function to aggregate all impactDao balances

        // Bob sets new price.
        vm.prank(bob);
        kaliBerger.setPrice(address(token_1), 1, 2 ether);

        // Validate setting of new price.
        assertEq(kaliBerger.getPrice(address(token_1), 1), 2 ether);

        // Validate balances.
        vm.prank(impactDao);
        kaliBerger.claim();
        assertEq(address(impactDao).balance, oldImpactDaoBalance + patronage);
        assertEq(address(kaliBerger).balance, oldBalance - address(impactDao).balance);

        // Validate patronage.
        vm.warp(5000);
        validatePatronageToCollect(token_1, 1);
    } // timestamp: 5000

    /// @notice Bob add deposits to maintain his ownership of token_1, token #1 for a longer period of time.
    function testSingleBuy_addDeposit() public payable {
        // Bob buys.
        testSingleBuy();
        vm.warp(4500);

        // Retrieve data for validation.
        address impactDao = kaliBerger.getImpactDao(address(token_1), 1);
        uint256 deposit = kaliBerger.getDeposit(address(token_1), 1);
        uint256 patronage = kaliBerger.patronageToCollect(address(token_1), 1);
        uint256 oldImpactDaoBalance = address(impactDao).balance + kaliBerger.getUnclaimed(impactDao); // Consider a function to aggregate all impactDao balances

        // Bob adds deposit.
        vm.prank(bob);
        kaliBerger.addDeposit{value: 0.5 ether}(address(token_1), 1, 0.5 ether);

        // Retrieve data for validation.
        uint256 oldBalance = address(kaliBerger).balance;

        // Validate deposit amount.
        assertEq(kaliBerger.getDeposit(address(token_1), 1), deposit + 0.5 ether - patronage);
        validatePatronageToCollect(token_1, 1);

        // Validate balances.
        vm.prank(impactDao);
        kaliBerger.claim();
        assertEq(address(impactDao).balance, oldImpactDaoBalance + patronage);
        assertEq(address(kaliBerger).balance, oldBalance - address(impactDao).balance);
    } // timestamp: 4500

    /// @notice DAO changes tax.
    function testSingleBuy_setTax() public payable {
        // Bob buys.
        testSingleBuy();

        // Validate patronage to collect.
        vm.warp(6600);
        validatePatronageToCollect(token_1, 1);

        // Set new tax rate.
        vm.prank(dao);
        kaliBerger.setTax(address(token_1), 1, 30);

        // Validate patronage to collect.
        vm.warp(9200);
        validatePatronageToCollect(token_1, 1);

        // Validate patron balances.
        balanceDao(10000, address(token_1), 1, alfred);
    }

    /// @notice Charlie add deposits to help Bob maintain ownership of token_1, token #1 for a longer period of time.
    function testSingleBuy_addDeposit_byOthers() public payable {
        // Bob buys.
        testSingleBuy();
        vm.warp(4500);

        // Retrieve data for validation.
        address impactDao = kaliBerger.getImpactDao(address(token_1), 1);
        uint256 deposit = kaliBerger.getDeposit(address(token_1), 1);
        uint256 patronage = kaliBerger.patronageToCollect(address(token_1), 1);
        uint256 oldImpactDaoBalance = address(impactDao).balance + kaliBerger.getUnclaimed(impactDao); // Consider a function to aggregate all impactDao balances

        // Deal Charlie ether.
        vm.deal(charlie, 10 ether);

        // Charlie adds deposit.
        vm.prank(charlie);
        kaliBerger.addDeposit{value: 0.5 ether}(address(token_1), 1, 0.5 ether);

        // Retrieve data for validation.
        uint256 oldBalance = address(kaliBerger).balance;

        // Validate deposit amount.
        assertEq(kaliBerger.getDeposit(address(token_1), 1), deposit + 0.5 ether - patronage);
        validatePatronageToCollect(token_1, 1);

        // Validate balances.
        vm.prank(impactDao);
        kaliBerger.claim();
        assertEq(address(impactDao).balance, oldImpactDaoBalance + patronage);
        assertEq(address(kaliBerger).balance, oldBalance - address(impactDao).balance);
    } // timestamp: 4500

    /// @notice Bob exits a portion of his previous deposit.
    function testSingleBuy_exit() public payable {
        testSingleBuy_addDeposit();
        vm.warp(6000);

        // Retrieve data for validation.
        address impactDao = kaliBerger.getImpactDao(address(token_1), 1);
        uint256 patronage = kaliBerger.patronageToCollect(address(token_1), 1);
        uint256 deposit = kaliBerger.getDeposit(address(token_1), 1);
        uint256 oldImpactDaoBalance = address(impactDao).balance + kaliBerger.getUnclaimed(impactDao); // Consider a function to aggregate all impactDao balances
        uint256 oldBalance = address(kaliBerger).balance;

        // Bob exits a portion of deposit.
        vm.prank(bob);
        kaliBerger.exit(address(token_1), 1, 0.3 ether);

        // Validate deposit amount.
        assertEq(kaliBerger.getDeposit(address(token_1), 1), deposit - 0.3 ether - patronage);
        validatePatronageToCollect(token_1, 1);

        // Retrieve data for validation.
        uint256 unclaimed = kaliBerger.getUnclaimed(impactDao);

        // Validate balances.
        vm.prank(impactDao);
        kaliBerger.claim();
        assertEq(address(impactDao).balance, oldImpactDaoBalance + patronage);
        assertEq(address(kaliBerger).balance, oldBalance - 0.3 ether - unclaimed);
    } // timestamp: 6000

    /// @notice Bob ragequits by removing all of his deposit, triggering foreclosure.
    function testSingleBuy_ragequit() public payable {
        testSingleBuy_addDeposit();
        vm.warp(6000);

        // Retrieve data for validation.
        address impactDao = kaliBerger.getImpactDao(address(token_1), 1);
        uint256 patronage = kaliBerger.patronageToCollect(address(token_1), 1);
        uint256 deposit = kaliBerger.getDeposit(address(token_1), 1);
        uint256 oldImpactDaoBalance = address(impactDao).balance + kaliBerger.getUnclaimed(impactDao); // Consider a function to aggregate all impactDao balances

        // Bob withdraws all of deposit.
        vm.prank(bob);
        kaliBerger.exit(address(token_1), 1, deposit - patronage);

        // Validate patronage amount.
        assertEq(kaliBerger.getDeposit(address(token_1), 1), 0);
        assertEq(token_1.balanceOf(address(kaliBerger)), 1);
        validatePatronageToCollect(token_1, 1);

        // Validate balances.
        vm.prank(impactDao);
        kaliBerger.claim();
        assertEq(address(impactDao).balance, oldImpactDaoBalance + patronage);
        assertEq(address(kaliBerger).balance, 0);
        // emit log_uint(unclaimed);
        // emit log_uint(address(impactDao).balance);
        // emit log_uint(address(kaliBerger).balance);
    } // timestamp: 6000

    /// @notice Charlie buys token_1, tokenId #1 and declares new price for sale.
    function testSingleBuy_secondBuy() public payable {
        // Escrow & approve
        testSingleBuy();
        vm.warp(4500);

        // Retrieve data for validation.
        address impactDao = kaliBerger.getImpactDao(address(token_1), 1);
        uint256 patronage = kaliBerger.patronageToCollect(address(token_1), 1);
        uint256 oldImpactDaoBalance = address(impactDao).balance + kaliBerger.getUnclaimed(impactDao); // Consider a function to aggregate all impactDao balances

        // Deal Charlie ether
        vm.deal(charlie, 10 ether);

        // Charlie buys
        vm.prank(charlie);
        kaliBerger.buy{value: 1.3 ether}(address(token_1), 1, 1.5 ether, 1 ether);

        // emit log_uint(oldImpactDaoBalance);
        // emit log_uint(patronage);
        // emit log_uint(address(impactDao).balance);
        // emit log_uint(address(kaliBerger).balance);
        // emit log_uint(kaliBerger.getUnclaimed(address(impactDao)));

        // Validate pre-claim balance.
        assertEq(address(kaliBerger).balance, 0.3 ether + kaliBerger.getUnclaimed(address(impactDao)));

        // Validate contract balances.
        vm.prank(impactDao);
        kaliBerger.claim();
        assertEq(address(impactDao).balance, oldImpactDaoBalance + patronage);
        assertEq(address(charlie).balance, 8.7 ether);

        // Validate ownership of Patron Certificate for token_1, #1.
        assertEq(
            IPatronCertificate(address(patronCertificate)).ownerOf(
                IPatronCertificate(address(patronCertificate)).getTokenId(address(token_1), 1)
            ),
            charlie
        );

        // Balance DAO.
        balanceDao(6000, address(token_1), 1, alfred);
    } // timestamp: 6000

    /// @notice After the initial purchase by Bob centuries ago, Charlie came along in year 2055 to purchase the now foreclosed token_1, #1.
    function testSingleBuy_foreclosedSecondBuy() public payable {
        // Buy.
        testSingleBuy();
        vm.warp(2707346409);

        // Retrieve data for validation.
        address impactDao = kaliBerger.getImpactDao(address(token_1), 1);

        // Deal Charlie ether.
        vm.deal(charlie, 10 ether);

        // Bob defaults. Charlie buys.
        uint256 value = 0.1 ether;
        vm.prank(charlie);
        kaliBerger.buy{value: value}(address(token_1), 1, 3 ether, 0);

        // Validate pre-claim balance.
        assertEq(address(kaliBerger).balance, value + kaliBerger.getUnclaimed(impactDao));

        // Validate contract balances.
        vm.prank(impactDao);
        kaliBerger.claim();
        assertEq(address(impactDao).balance, 0.1 ether); // ImpactDAO should have Bob's full deposit of 0.1 ether.
        assertEq(address(charlie).balance, 9.9 ether);

        // Validate ownership of Patron Certificate for token_1, #1.
        assertEq(
            IPatronCertificate(address(patronCertificate)).ownerOf(
                IPatronCertificate(address(patronCertificate)).getTokenId(address(token_1), 1)
            ),
            charlie
        );

        // Balance DAO.
        balanceDao(2707346509, address(token_1), 1, alfred);
    } // timestamp: 2707346509

    /// @notice Earn buys token_1, tokenId #1 and declares new price for sale.
    function testSingleBuy_thirdBuy() public payable {
        // Continuing from second buy by Charlie.
        testSingleBuy_secondBuy();
        vm.warp(100000);

        // Retrieve data for validation.
        address impactDao = kaliBerger.getImpactDao(address(token_1), 1);
        uint256 patronage = kaliBerger.patronageToCollect(address(token_1), 1);
        uint256 oldImpactDaoBalance = address(impactDao).balance + kaliBerger.getUnclaimed(impactDao); // Consider a function to aggregate all impactDao balances

        // Deal Charlie ether.
        vm.deal(earn, 10 ether);

        // Charlie buys.
        vm.prank(earn);
        kaliBerger.buy{value: 1.6 ether}(address(token_1), 1, 5 ether, 1.5 ether);

        // emit log_uint(oldImpactDaoBalance);
        // emit log_uint(patronage);
        // emit log_uint(address(impactDao).balance);
        // emit log_uint(address(kaliBerger).balance);
        // emit log_uint(kaliBerger.getUnclaimed(address(impactDao)));

        // Validate pre-claim balance.
        // assertEq(address(kaliBerger).balance, 0.3 ether + kaliBerger.getUnclaimed(address(impactDao)));

        // Validate contract balances.
        vm.prank(impactDao);
        kaliBerger.claim();
        assertEq(address(impactDao).balance, oldImpactDaoBalance + patronage);
        assertEq(address(earn).balance, 8.4 ether);

        // Validate ownership of Patron Certificate for token_1, #1.
        assertEq(
            IPatronCertificate(address(patronCertificate)).ownerOf(
                IPatronCertificate(address(patronCertificate)).getTokenId(address(token_1), 1)
            ),
            earn
        );

        // Balance DAO.
        balanceDao(200000, address(token_1), 1, alfred);
    } // timestamp: 200000

    /// @notice Alfred withdraws token_1, tokenId #1.
    function testSingleBuy_pull() public payable {
        uint256 timestamp = 10000000;
        // Continuing from third buy by Earn.
        testSingleBuy_thirdBuy();
        vm.warp(timestamp);
        // emit log_uint(timestamp);

        vm.prank(alfred);
        kaliBerger.pull(address(token_1), 1);

        // Validate.
        assertEq(token_1.balanceOf(alfred), 1);
        assertEq(token_1.balanceOf(address(kaliBerger)), 0);
        assertEq(kaliBerger.getPrice(address(token_1), 1), 0);
        assertEq(kaliBerger.getDeposit(address(token_1), 1), 0);
        assertEq(kaliBerger.getTokenPurchaseStatus(address(token_1), 1), false);
        balanceDao(timestamp, address(token_1), 1, alfred);
    } // timestamp: 10000000

    /// -----------------------------------------------------------------------
    /// testSingleBuy Logic - Multiple Tokens
    /// -----------------------------------------------------------------------

    /// @notice Darius buys all tokens and declares new prices for each
    function testMultipleBuy() public payable {
        // Escrow & approve
        testApprove();
        vm.warp(3000);

        // Deal Darius ether
        vm.deal(darius, 10 ether);

        // Darius buys
        vm.prank(darius);
        kaliBerger.buy{value: 0.1 ether}(address(token_1), 1, 1 ether, 0);
        vm.prank(darius);
        kaliBerger.buy{value: 0.1 ether}(address(token_2), 1, 1 ether, 0);
        vm.prank(darius);
        kaliBerger.buy{value: 0.1 ether}(address(token_3), 1, 1 ether, 0);
        vm.warp(3100);

        // Validate balances.
        assertEq(address(kaliBerger).balance, 0.3 ether);
        assertEq(address(darius).balance, 9.7 ether);

        // Validate summoning of ImpactDAO.
        assertEq(kaliBerger.getBergerCount(), 3);

        // Validate patronage logic for calculating amount of patronage to collect.
        validatePatronageToCollect(token_1, 1);
        validatePatronageToCollect(token_2, 1);
        validatePatronageToCollect(token_3, 1);

        // Validate ownership of Patron Certificate for token_1, #1.
        assertEq(
            IPatronCertificate(address(patronCertificate)).ownerOf(
                IPatronCertificate(address(patronCertificate)).getTokenId(address(token_1), 1)
            ),
            darius
        );
        assertEq(
            IPatronCertificate(address(patronCertificate)).ownerOf(
                IPatronCertificate(address(patronCertificate)).getTokenId(address(token_2), 1)
            ),
            darius
        );
        assertEq(
            IPatronCertificate(address(patronCertificate)).ownerOf(
                IPatronCertificate(address(patronCertificate)).getTokenId(address(token_3), 1)
            ),
            darius
        );

        // Balance DAO.
        balanceDao(4000, address(token_1), 1, alfred);
        balanceDao(4000, address(token_2), 1, bob);
        balanceDao(4000, address(token_3), 1, charlie);
    } // timestamp: 4000

    /// -----------------------------------------------------------------------
    /// Custom Error Test Logic
    /// -----------------------------------------------------------------------

    /// @notice With KaliBerger uninitialized, Bob tries to buy tokens and gets an Uninitialized() error.
    function testUninitialized() public payable {
        vm.warp(100);

        // Deal Bob ether
        vm.deal(bob, 10 ether);

        // Bob buys
        vm.expectRevert(KaliBerger.NotInitialized.selector);
        vm.prank(bob);
        kaliBerger.buy{value: 0.1 ether}(address(token_3), 1, 1 ether, 0);
    } // timestamp: 1500

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
        vm.warp(4500);

        // Charlie tries to set new price on behalf of Alfred.
        vm.expectRevert(KaliBerger.NotAuthorized.selector);
        vm.prank(charlie);
        kaliBerger.setPrice(address(token_1), 1, 2 ether);
    } // timestamp: 5000

    /// @notice Bob withdraws too much and triggers InvalidExit() error.
    function testSingleBuy_exit_invalidExit() public payable {
        // Add deposit.
        testSingleBuy_addDeposit();
        vm.warp(5000);

        // InvalidExit()
        vm.expectRevert(KaliBerger.InvalidExit.selector);
        vm.prank(bob);
        kaliBerger.exit(address(token_1), 1, 1 ether);
    }

    /// @notice Charlie tries to withdraw from deposit and triggers NotAuthorized() error.
    function testSingleBuy_exit_byOthers() public payable {
        // Add deposit.
        testSingleBuy_addDeposit();
        vm.warp(5000);

        // InvalidExit()
        vm.expectRevert(KaliBerger.NotAuthorized.selector);
        vm.prank(charlie);
        kaliBerger.exit(address(token_1), 1, 0.2 ether);
    }

    /// @notice Alfred tries to withdraw token_1, tokenId #1 but cannot bc it has not
    ///         foreclosed yet.
    function testSingleBuy_pull_() public payable {
        // Continuing from third buy by Earn.
        testSingleBuy_secondBuy();

        // InvalidExit()
        vm.expectRevert(KaliBerger.InvalidExit.selector);
        vm.prank(alfred);
        kaliBerger.pull(address(token_1), 1);

        // Validate
        assertEq(token_1.balanceOf(alfred), 0);
        assertEq(token_1.balanceOf(address(kaliBerger)), 1);
    } // timestamp: 5500

    /// @notice Earn tries to withdraw token_1, tokenId #1 on behalf of Alfred,
    /// @notice but triggers NotAuthorized() error because Alfred is the creator of NFT.
    function testSingleBuy_pull_byOthers() public payable {
        uint256 timestamp = 10000000;
        // Continuing from third buy by Earn.
        testSingleBuy_thirdBuy();
        vm.warp(timestamp);
        // emit log_uint(timestamp);

        // Earn withdraws but errors out.
        vm.expectRevert(KaliBerger.NotAuthorized.selector);
        vm.prank(earn);
        kaliBerger.pull(address(token_1), 1);

        // Validate.
        assertEq(token_1.balanceOf(alfred), 0);
        assertEq(token_1.balanceOf(earn), 0);
        assertEq(token_1.balanceOf(address(kaliBerger)), 1);
        balanceDao(timestamp, address(token_1), 1, alfred);
    } // timestamp: 10000000

    function testReceiveETH() public payable {
        (bool sent,) = address(kaliBerger).call{value: 5 ether}("");
        assert(sent);
        assert(address(kaliBerger).balance == 5 ether);
    }
}
