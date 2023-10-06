// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {IERC721} from "lib/forge-std/src/interfaces/IERC721.sol";
import {MockERC721} from "lib/solbase/test/utils/mocks/MockERC721.sol";
import {KaliDAOfactory, KaliDAO} from "src/kalidao/KaliDAOfactory.sol";

import {Storage} from "src/Storage.sol";
import {IStorage} from "src/interface/IStorage.sol";
import {KaliBerger} from "src/KaliBerger.sol";
import {PatronCertificate} from "src/tokens/PatronCertificate.sol";

contract KaliBergerTest is Test {
    MockERC721 erc721;

    KaliDAOfactory factory;
    KaliDAO daoTemplate;

    Storage stor;
    KaliBerger kaliBerger;
    PatronCertificate patronCertificate;

    IStorage iStorage;

    /// @dev Users.
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public dummy = makeAddr("dummy");
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
    /// Kali Setup Tests
    /// -----------------------------------------------------------------------

    /// @notice Set up the testing suite.
    function setUp() public payable {
        // Deploy a KaliDAO factory
        daoTemplate = new KaliDAO();
        factory = new KaliDAOfactory(payable(daoTemplate));
        factory.deployKaliDAO(
            "Berger Council", "BC", " ", true, extensions, extensionsData, voters, shares, govSettings
        );

        // Deploy contract
        kaliBerger = new KaliBerger();
        vm.prank(dao);
        kaliBerger.initialize(dao, address(factory), address(patronCertificate));

        patronCertificate = new PatronCertificate(address(kaliBerger));
        vm.prank(dao);
        kaliBerger.setCertificateMinter(address(patronCertificate));

        // Mint Alice an ERC721
        erc721 = new MockERC721("TEST", "TEST");
        erc721.mint(alice, 1);
        assertEq(erc721.balanceOf(alice), 1);

        vm.warp(100);
    } // 100

    /// @notice Escrow ERC721
    function testEscrow() public payable {
        // Approve ERC721
        vm.prank(alice);
        erc721.approve(address(kaliBerger), 1);
        vm.warp(200);

        // Escrow
        vm.prank(alice);
        kaliBerger.escrow(address(erc721), 1);
        vm.warp(300);

        // Validate
        assertEq(erc721.balanceOf(alice), 0);
        assertEq(erc721.balanceOf(address(kaliBerger)), 1);
    } // 300

    /// @notice Approve ERC721 for purchase
    function testApprove() public payable {
        // Escrow
        testEscrow();
        vm.warp(400);

        // DAO approves
        vm.prank(dao);
        kaliBerger.approve(address(erc721), 1, true, "Cool NFT!");
        vm.warp(500);

        // Validate
        assertEq(kaliBerger.getTokenPurchaseStatus(address(erc721), 1), true);
        assertEq(kaliBerger.getTokenDetail(address(erc721), 1), "Cool NFT!");
        assertEq(kaliBerger.getOwner(address(erc721), 1), address(kaliBerger));
    } // 500

    /// @notice Calculate patronage to patronage after Approve
    function testApprove_PatronageToCollect() public payable {
        testApprove();
        vm.warp(600);

        // Validate
        uint256 amount = kaliBerger.getPrice(address(erc721), 1)
            * (block.timestamp - kaliBerger.getTimeLastCollected(address(erc721), 1))
            * kaliBerger.getTax(address(erc721), 1) / 365 days / 100;
        assertEq(kaliBerger.patronageToCollect(address(erc721), 1), amount);
    } // 600

    /// @notice Calculate patronage to collect after Approve
    function testApprove_NotForSale() public payable {
        // Escrow
        testEscrow();
        vm.warp(400);

        // DAO disapproves
        vm.prank(dao);
        kaliBerger.approve(address(erc721), 1, false, "Cool NFT!");
        vm.warp(500);

        // Validate
        assertEq(erc721.balanceOf(alice), 1);
        assertEq(erc721.balanceOf(address(kaliBerger)), 0);
        assertEq(kaliBerger.getTokenPurchaseStatus(address(erc721), 1), false);
    } // 500

    /// @notice Primary sale of ERC721
    function testBuy() public payable {
        // Escrow & approve
        testApprove();
        vm.warp(600);

        // Deal Bob ether
        vm.deal(bob, 10 ether);
        // emit log_uint(address(bob).balance);

        // Bob buys
        vm.prank(bob);
        kaliBerger.buy{value: 0.1 ether}(address(erc721), 1, 1 ether, 0);
        vm.warp(700);

        // Validate
        assertEq(address(kaliBerger).balance, 0.1 ether);
    } // 700

    /// @notice Calculate patronage to collect after Buy
    function testBuy_PatronageToCollect() public payable {
        // Bob buys
        testBuy();

        // Validate
        uint256 amount = kaliBerger.getPrice(address(erc721), 1)
            * (block.timestamp - kaliBerger.getTimeLastCollected(address(erc721), 1))
            * kaliBerger.getTax(address(erc721), 1) / 365 days / 100;
        assertEq(kaliBerger.patronageToCollect(address(erc721), 1), amount);
    }

    /// @notice Secondary sale of ERC721
    function testSecondaryBuy() public payable {
        // Escrow & approve
        testBuy();
        vm.warp(900);

        // Deal Charlie ether
        vm.deal(charlie, 10 ether);
        // emit log_uint(address(bob).balance);

        // Charlie buys
        vm.prank(charlie);
        kaliBerger.buy{value: 1.1 ether}(address(erc721), 1, 1.5 ether, 1 ether);
        vm.warp(1000);

        // Validate
        // TODO: Add more validation checks, including balance at impactDao
        emit log_uint(address(kaliBerger).balance);
        emit log_uint(address(bob).balance);
    } // 900

    function testReceiveETH() public payable {
        (bool sent,) = address(kaliBerger).call{value: 5 ether}("");
        assert(sent);
        assert(address(kaliBerger).balance == 5 ether);
    }
}
