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
import {PatronCertificate} from "src/tokens/PatronCertificate.sol";

contract KaliBergerTest is Test {
    MockERC721 token_1;
    MockERC721 token_2;
    MockERC721 token_3;

    KaliDAOfactory factory;
    KaliDAO daoTemplate;

    Storage stor;
    KaliBerger kaliBerger;
    PatronCertificate patronCertificate;

    IStorage iStorage;

    /// @dev Users.
    address payable public alice = payable(makeAddr("alice"));
    address payable public bob = payable(makeAddr("bob"));
    address payable public charlie = payable(makeAddr("charlie"));
    address payable public dummy = payable(makeAddr("dummy"));
    address payable public dao = payable(makeAddr("dao"));

    /// @dev Helpers.
    string internal constant description = "TEST";
    bytes32 internal constant name1 = 0x5445535400000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant name2 = 0x5445535432000000000000000000000000000000000000000000000000000000;

    /// @dev KaliDAO init params
    address[] extensions;
    bytes[] extensionsData;
    address[] voters = [address(alice)];
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

        // Mint Alice an ERC721.
        mintErc721(token_1, 1, alice);

        // Mint Bob an ERC721.
        mintErc721(token_2, 1, bob);

        // Mint Charlie an ERC721.
        mintErc721(token_3, 1, charlie);

        vm.warp(100);
    } // 100

    /// -----------------------------------------------------------------------
    /// KaliBerger Initial Setup
    /// -----------------------------------------------------------------------

    /// @notice Escrow ERC721
    function escrow(address user, MockERC721 token, uint256 tokenId) internal {
        // Approve KaliBerger to transfer ERC721
        vm.prank(user);
        token.approve(address(kaliBerger), tokenId);
        vm.warp(200);

        // User escrows ERC721 with KaliBerger
        vm.prank(user);
        kaliBerger.escrow(address(token), tokenId);
        vm.warp(300);

        // Validate
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(kaliBerger)), tokenId);
    } // 300

    /// @notice Approve ERC721 for purchase
    function approve(MockERC721 token, uint256 tokenId) public payable {
        // DAO approves ERC721 for sale
        vm.prank(dao);
        kaliBerger.approve(address(token), tokenId, true, "Cool NFT!");

        // Validate
        assertEq(kaliBerger.getTokenPurchaseStatus(address(token), tokenId), true);
        assertEq(kaliBerger.getTokenDetail(address(token), tokenId), "Cool NFT!");
        assertEq(kaliBerger.getOwner(address(token), tokenId), address(kaliBerger));
    }

    /// -----------------------------------------------------------------------
    /// Helper Logic
    /// -----------------------------------------------------------------------

    function deployErc721() internal returns (MockERC721 token) {
        token = new MockERC721("TEST", "TEST");
    }

    function mintErc721(MockERC721 token, uint256 tokenId, address recipient) internal {
        if (address(token) == address(0)) {
            token = deployErc721();
        }

        // Mint recipient an ERC721
        token.mint(recipient, tokenId);
        assertEq(token.balanceOf(recipient), tokenId);
    }

    function validatePatronageToCollect(MockERC721 token, uint256 tokenId) internal {
        uint256 amount = kaliBerger.getPrice(address(token), tokenId)
            * (block.timestamp - kaliBerger.getTimeLastCollected(address(token), tokenId))
            * kaliBerger.getTax(address(token), tokenId) / 365 days / 100;
        assertEq(kaliBerger.patronageToCollect(address(token), tokenId), amount);
        // emit log_uint(amount);
    }

    /// @notice Anyone can rebalance DAO tokens at any time.
    function balanceDao(uint256 timestamp, address token, uint256 tokenId, address creator) internal {
        // Validate
        vm.warp(timestamp);

        vm.prank(dummy);
        kaliBerger.balanceDao(token, tokenId);

        address impactDao = kaliBerger.getImpactDao(token, tokenId);
        uint256 creator_balance = IERC20(impactDao).balanceOf(creator);
        uint256 alice_balance = IERC20(impactDao).balanceOf(alice);
        uint256 bob_balance = IERC20(impactDao).balanceOf(bob);
        uint256 charlie_balance = IERC20(impactDao).balanceOf(charlie);

        if (creator == alice) assertEq(creator_balance, bob_balance + charlie_balance);
        if (creator == bob) assertEq(creator_balance, alice_balance + charlie_balance);
        if (creator == charlie) assertEq(creator_balance, alice_balance + bob_balance);
        emit log_uint(alice_balance);
        emit log_uint(bob_balance);
        emit log_uint(charlie_balance);
    }

    /// -----------------------------------------------------------------------
    /// Test Logic
    /// -----------------------------------------------------------------------

    /// @notice Alice escrows tokenId #1 of token_1
    function testEscrow() public payable {
        escrow(alice, token_1, 1);
        escrow(bob, token_2, 1);
        escrow(charlie, token_3, 1);
    } // 300

    /// @notice DAO approves token_1, tokenId #1 for purchase and adds custom detail
    function testApprove() public payable {
        // Escrow
        testEscrow(); // 300

        // DAO approves
        vm.warp(500);
        approve(token_1, 1); // 500

        vm.warp(1000);
        approve(token_2, 1); // 1000

        vm.warp(2000);
        approve(token_3, 1); // 2000
    } // 500, 1000, 2000

    /// @notice Calculate patronage to patronage after Approve
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
        assertEq(token_1.balanceOf(alice), 1);
        assertEq(token_1.balanceOf(address(kaliBerger)), 0);
        assertEq(kaliBerger.getTokenPurchaseStatus(address(token_1), 1), false);
    } // timestamp: 500

    /// @notice Bob buys token_1, tokenId #1 and announces a new price for sale
    function testBuy() public payable {
        // Escrow & approve
        testApprove();
        vm.warp(3000);

        // Deal Bob ether
        vm.deal(bob, 10 ether);
        // emit log_uint(address(bob).balance);

        // Bob buys
        vm.prank(bob);
        kaliBerger.buy{value: 0.1 ether}(address(token_1), 1, 1 ether, 0);
        vm.warp(3100);

        // Validate
        assertEq(address(kaliBerger).balance, 0.1 ether);
        assertEq(address(bob).balance, 9.9 ether);
        assertEq(kaliBerger.getBergerCount(), 1);
        validatePatronageToCollect(token_1, 1);

        balanceDao(4000, address(token_1), 1, alice);
    } // timestamp: 4000

    /// @notice Unsatisfied with the first price, Bob sets a new price.
    function testBuy_setPrice() public payable {
        // Bob buys
        testBuy();

        // Bob sets new price
        vm.prank(bob);
        kaliBerger.setPrice(address(token_1), 1, 2 ether);

        // Validate
        vm.warp(4500);
        assertEq(kaliBerger.getPrice(address(token_1), 1), 2 ether);
        validatePatronageToCollect(token_1, 1);
    }

    /// @notice Bob add deposits to maintain his ownership of token_1, token #1 for a longer period of time.
    function testBuy_addDeposit() public payable {
        // Bob buys
        testBuy();

        uint256 _deposit = kaliBerger.getDeposit(address(token_1), 1);

        // Bob adds deposit
        vm.prank(bob);
        kaliBerger.addDeposit{value: 0.5 ether}(address(token_1), 1);

        // Validate deposit amount
        assertEq(
            kaliBerger.getDeposit(address(token_1), 1),
            _deposit + 0.5 ether - kaliBerger.patronageToCollect(address(token_1), 1)
        );
        validatePatronageToCollect(token_1, 1);
    } // timestamp: 4000

    /// @notice Bob exits a portion of his previous deposit.
    function testBuy_exit() public payable {
        testBuy_addDeposit();
        vm.warp(4500);

        uint256 _deposit = kaliBerger.getDeposit(address(token_1), 1);
        // emit log_uint(_deposit);
        uint256 patronage = kaliBerger.patronageToCollect(address(token_1), 1);
        // emit log_uint(patronage);

        // Bob exits a portion of deposit.
        vm.prank(bob);
        kaliBerger.exit(address(token_1), 1, 0.3 ether);

        // Validate deposit amount
        assertEq(kaliBerger.getDeposit(address(token_1), 1), _deposit - 0.3 ether - patronage);
        validatePatronageToCollect(token_1, 1);
    } // timestamp: 4500

    /// @notice Bob ragequits by removing all of his deposit, triggering foreclosure.
    function testBuy_ragequit() public payable {
        testBuy_addDeposit();

        vm.warp(5000);

        uint256 _deposit = kaliBerger.getDeposit(address(token_1), 1);
        // emit log_uint(_deposit);
        uint256 patronage = kaliBerger.patronageToCollect(address(token_1), 1);
        // emit log_uint(patronage);

        // Bob withdraws all of deposit.
        vm.prank(bob);
        kaliBerger.exit(address(token_1), 1, _deposit - patronage);

        // Validate
        assertEq(kaliBerger.getDeposit(address(token_1), 1), 0);
        assertEq(token_1.balanceOf(address(kaliBerger)), 1);
        validatePatronageToCollect(token_1, 1);
    }

    /// @notice Bob withdraws too much and triggers InvalidExit() error.
    function testBuy_invalidExit() public payable {
        testBuy_addDeposit();

        vm.warp(5000);

        // InvalidExit()
        vm.expectRevert(KaliBerger.InvalidExit.selector);
        vm.prank(bob);
        kaliBerger.exit(address(token_1), 1, 1 ether);
    }

    /// @notice Charlie buys token_1, tokenId #1 and announces new price for sale.
    function testBuy_SecondarySale() public payable {
        // Escrow & approve
        testBuy();
        vm.warp(4500);

        // Deal Charlie ether
        vm.deal(charlie, 10 ether);

        // Charlie buys
        vm.prank(charlie);
        kaliBerger.buy{value: 1.1 ether}(address(token_1), 1, 1.5 ether, 1 ether);
        vm.warp(5000);

        // Validate
        balanceDao(5500, address(token_1), 1, alice);
    } // timestamp: 5500

    function testReceiveETH() public payable {
        (bool sent,) = address(kaliBerger).call{value: 5 ether}("");
        assert(sent);
        assert(address(kaliBerger).balance == 5 ether);
    }
}
