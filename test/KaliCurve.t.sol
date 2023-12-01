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
import {IKaliCurve, CurveType} from "src/interface/IKaliCurve.sol";

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

    /// -----------------------------------------------------------------------
    /// Curve Setup Test
    /// -----------------------------------------------------------------------

    function testCurve_DaoTreasury() public payable {
        initialize(dao, address(factory));

        setupCurve(0, alfred, CurveType.LINEAR, 0.0001 ether, 10, 1, 1, 0, true, true);
    }

    function testCurve_UserTreasury() public payable {
        initialize(dao, address(factory));

        setupCurve(0, alfred, CurveType.LINEAR, 0.0001 ether, 10, 1, 1, 0, true, false);
    }

    function testCurve_InvalidCurveParam() public payable {}

    function testCurve_NotAuthorized() public payable {}

    /// -----------------------------------------------------------------------
    /// Donate Test
    /// -----------------------------------------------------------------------

    function testDonate_DaoTreasury() public payable {
        testCurve_DaoTreasury();
        vm.warp(block.timestamp + 100);

        uint256 amount = kaliCurve.getMintPrice(kaliCurve.getCurveCount());
        emit log_uint(amount);

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        kaliCurve.donate{value: amount}(kaliCurve.getCurveCount(), bob, amount);

        // Validate.
        // assertEq();
    }

    function testDonate_UserTreasury() public payable {
        testCurve_UserTreasury();
        vm.warp(block.timestamp + 100);

        uint256 amount = kaliCurve.getMintPrice(kaliCurve.getCurveCount());
        emit log_uint(amount);

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        kaliCurve.donate{value: amount}(kaliCurve.getCurveCount(), bob, amount);

        // Validate.
        // assertEq();
    }

    function testDonate_NotInitialized() public payable {}

    function testDonate_NotAuthorized() public payable {}

    function testDonate_InvalidMint() public payable {}

    function testLeave() public payable {}

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
        assertEq(kaliCurve.getKaliDaoFactory(), address(factory));
    }

    /// @notice Set up a curve.
    function setupCurve(
        uint256 curveId,
        address user,
        CurveType curveType,
        uint256 scale,
        uint256 burnRatio,
        uint256 constant_a,
        uint256 constant_b,
        uint256 constant_c,
        bool canMint,
        bool daoTreasury
    ) internal {
        // Set up curve.
        vm.prank(user);
        kaliCurve.curve(
            curveId, user, curveType, scale, burnRatio, constant_a, constant_b, constant_c, canMint, daoTreasury
        );

        // Validate.
        uint256 count = kaliCurve.getCurveCount();
        assertEq(count, 1);
        assertEq(kaliCurve.getCurveOwner(count), user);
        assertEq(kaliCurve.getCurveScale(count), scale);
        assertEq(kaliCurve.getCurveBurnRatio(count), burnRatio);
        assertEq(kaliCurve.getCurveMintStatus(count), canMint);
        assertEq(kaliCurve.getCurveTreasuryStatus(count), daoTreasury);
        assertEq(kaliCurve.getCurveSupply(count), 0);
        assertEq(uint256(kaliCurve.getCurveType(count)), uint256(CurveType.LINEAR));
        assertEq(kaliCurve.getMintConstantA(count), constant_a);
        assertEq(kaliCurve.getMintConstantB(count), constant_b);
        assertEq(kaliCurve.getMintConstantC(count), constant_c);
        assertEq(kaliCurve.getBurnConstantA(count), 0);
        assertEq(kaliCurve.getBurnConstantB(count), 0);
        assertEq(kaliCurve.getBurnConstantC(count), 0);
    }
}
