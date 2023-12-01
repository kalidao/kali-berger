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
import {KaliCurve} from "src/KaliCurve.sol";

contract KaliCurveTest is Test {
    KaliDAOfactory factory;
    KaliDAO daoTemplate;

    Storage stor;
    KaliCurve kaliCurve;
    KaliCurve kaliCurve_uninitialized;

    /// @dev Users.
    address payable public alfred = payable(makeAddr("alfred"));
    address payable public bob = payable(makeAddr("bob"));
    address payable public charlie = payable(makeAddr("charlie"));
    address payable public darius = payable(makeAddr("darius"));
    address payable public earn = payable(makeAddr("earn"));
    address payable public dao = payable(makeAddr("dao"));

    /// @dev Helpers.
    string public testString = "TEST";

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
        factory.deployKaliDAO("Curve Council", "CC", " ", true, extensions, extensionsData, voters, tokens, govSettings);

        // Deploy and initialize KaliCurve contract.
        kaliCurve = new KaliCurve();
        kaliCurve_uninitialized = new KaliCurve();
        vm.warp(block.timestamp + 100);
    }

    /// -----------------------------------------------------------------------
    /// Initialization Test
    /// -----------------------------------------------------------------------

    /// @notice Initialize KaliCurve.
    function testInitialized() public payable {
        initialize(dao, address(factory));
        assertEq(kaliCurve.getKaliDaoFactory(), address(factory));
    }

    /// @notice Update KaliDAO factory.
    function testFactory() public payable {
        initialize(dao, address(factory));

        vm.prank(dao);
        kaliCurve.setKaliDaoFactory(earn);
        assertEq(kaliCurve.getKaliDaoFactory(), address(earn));
    }

    /// @notice Update KaliDAO factory.
    function testNotInitialized() public payable {
        vm.expectRevert(KaliCurve.NotInitialized.selector);
        vm.prank(dao);
        kaliCurve.setKaliDaoFactory(earn);
    }
    /// @notice With kaliCurve uninitialized, Bob tries to buy tokens and gets an NotInitialized() error.

    /// -----------------------------------------------------------------------
    ///  Test
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// Buy Test
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// Getter Test
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// Custom Error Test
    /// -----------------------------------------------------------------------

    function testReceiveETH() public payable {
        (bool sent,) = address(kaliCurve).call{value: 5 ether}("");
        assert(sent);
        assert(address(kaliCurve).balance == 5 ether);
    }

    /// -----------------------------------------------------------------------
    /// Helper Logic
    /// -----------------------------------------------------------------------

    /// @notice Initialize kaliCurve.
    function initialize(address _dao, address _factory) internal {
        kaliCurve.initialize(_dao, _factory);
    }
}
