// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {MockERC721} from "lib/solbase/test/utils/mocks/MockERC721.sol";
import {KaliDAOfactory, KaliDAO} from "src/kalidao/KaliDAOfactory.sol";

import {Storage} from "src/Storage.sol";
import {IStorage} from "src/interface/IStorage.sol";
import {KaliBerger} from "src/KaliBerger.sol";

contract KaliBergerTest is Test {
    MockERC721 erc721;

    KaliDAOfactory factory;
    KaliDAO daoTemplate;

    Storage stor;
    KaliBerger kaliBerger;

    IStorage iStorage;

    /// @dev Users.
    address public immutable alice = makeAddr("alice");
    address public immutable bob = makeAddr("bob");
    address public immutable charlie = makeAddr("charlie");
    address public immutable dummy = makeAddr("dummy");
    address payable public immutable dao = payable(makeAddr("dao"));

    /// @dev Helpers.
    string internal constant description = "TEST";
    bytes32 internal constant name1 = 0x5445535400000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant name2 = 0x5445535432000000000000000000000000000000000000000000000000000000;

    /// -----------------------------------------------------------------------
    /// Kali Setup Tests
    /// -----------------------------------------------------------------------

    /// @notice Set up the testing suite.
    function setUp() public payable {
        // Mint Alice an ERC721
        erc721 = new MockERC721("TEST", "TEST");
        erc721.mint(alice, 1);
        assertEq(erc721.balanceOf(alice), 1);

        // Deploy a KaliDAO factory
        daoTemplate = new KaliDAO();
        factory = new KaliDAOfactory(payable(daoTemplate));

        // Deploy contract
        kaliBerger = new KaliBerger();
        vm.prank(dao);
        kaliBerger.initialize(dao, address(factory));

        vm.warp(100);
    }

    function testEscrow() public payable {
        // Approve ERC721
        vm.prank(alice);
        erc721.approve(address(kaliBerger), 1);
        vm.warp(200);

        // Escrow
        vm.prank(alice);
        kaliBerger.escrow(address(erc721), 1, 1 ether);
        vm.warp(300);

        // Validation
        assertEq(erc721.balanceOf(alice), 0);
        assertEq(erc721.balanceOf(address(kaliBerger)), 1);
    }

    function testApprove() public payable {
        // Escrow
        testEscrow();
        vm.warp(400);

        // DAO approves
        vm.prank(dao);
        kaliBerger.approve(address(erc721), 1, true);
        vm.warp(500);

        // Validation
        assertEq(kaliBerger.getTokenStatus(address(erc721), 1), true);
    }

    function testApprove_PatronageToCollect() public payable {
        testApprove();
        vm.warp(600);

        uint256 amount = kaliBerger.getPrice(address(erc721), 1)
            * (block.timestamp - kaliBerger.getTimeLastCollected(address(erc721), 1))
            * kaliBerger.getTax(address(erc721), 1) / 365 days / 100;

        // emit log_uint(block.timestamp);
        // emit log_uint((block.timestamp - kaliBerger.getTimeLastCollected(address(erc721), 1)));
        // emit log_uint(365 days);
        // emit log_uint(kaliBerger.patronageToCollect(address(erc721), 1));
        // emit log_uint(kaliBerger.getTimeLastCollected(address(erc721), 1));
        assertEq(kaliBerger.patronageToCollect(address(erc721), 1), amount);
    }

    // function testBuy() public payable {
    //     // Escrow & approve
    //     testApprove();

    //     // Fastforward
    //     vm.warp(100);

    //     // Bob buys
    //     vm.prank(bob);
    //     kaliBerger.buy(address(erc721), 1, 2 ether, 1 ether);
    // }

    function testReceiveETH() public payable {
        (bool sent,) = address(kaliBerger).call{value: 5 ether}("");
        assert(sent);
        assert(address(kaliBerger).balance == 5 ether);
    }
}
