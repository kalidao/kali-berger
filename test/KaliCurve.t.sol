// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {IERC721} from "lib/forge-std/src/interfaces/IERC721.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {MockERC721} from "lib/solbase/test/utils/mocks/MockERC721.sol";
import {KaliDAOfactory, KaliDAO} from "src/kalidao/KaliDAOfactory.sol";
import {IKaliTokenManager} from "src/interface/IKaliTokenManager.sol";

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
    address payable public alice = payable(makeAddr("alice"));
    address payable public bob = payable(makeAddr("bob"));
    address payable public charlie = payable(makeAddr("charlie"));
    address payable public david = payable(makeAddr("david"));
    address payable public ellie = payable(makeAddr("ellie"));
    address payable public dao = payable(makeAddr("dao"));

    /// @dev Helpers.
    string public testString = "TEST";

    /// @dev KaliDAO init params
    address[] extensions;
    bytes[] extensionsData;
    address[] voters = [address(alice)];
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
        kaliCurve.setKaliDaoFactory(ellie);
        assertEq(kaliCurve.getKaliDaoFactory(), address(ellie));
    }

    /// @notice Update KaliDAO factory.
    function testNotInitialized() public payable {
        vm.expectRevert(KaliCurve.NotInitialized.selector);
        vm.prank(dao);
        kaliCurve.setKaliDaoFactory(ellie);
    }

    /// -----------------------------------------------------------------------
    /// Curve Test - DAO Treasury
    /// -----------------------------------------------------------------------

    function testCurveWithDaoTreasury() public payable {
        initialize(dao, address(factory));

        setupCurve(
            CurveType.LINEAR, true, true, alice, uint96(0.0001 ether), uint16(10), uint48(1), uint48(1), uint48(0)
        );
    }

    function testCurveWithDaoTreasury_SetCurveData() public payable {
        testCurveWithDaoTreasury();
        vm.warp(block.timestamp + 100);

        uint256 count = kaliCurve.getCurveCount();
        uint256 data = kaliCurve.encodeCurveData(100, 10, 20, 15, 0);

        vm.prank(alice);
        kaliCurve.setCurveData(count, data);

        (uint256 _scale, uint256 _ratio, uint256 _constant_a, uint256 _constant_b, uint256 _constant_c) =
            kaliCurve.getCurveData(kaliCurve.getCurveCount());
        assertEq(_scale, uint96(100));
        assertEq(_ratio, uint16(10));
        assertEq(_constant_a, uint48(20));
        assertEq(_constant_b, uint48(15));
        assertEq(_constant_c, uint48(0));
    }

    function testCurveWithDaoTreasury_SetCurveData_NotOwner(
        uint96 scale,
        uint16 ratio,
        uint48 constant_a,
        uint48 constant_b,
        uint48 constant_c
    ) public payable {
        testCurveWithDaoTreasury();
        vm.warp(block.timestamp + 100);

        uint256 count = kaliCurve.getCurveCount();
        uint256 data = kaliCurve.encodeCurveData(100, 10, 20, 15, 0);

        vm.expectRevert(KaliCurve.NotAuthorized.selector);
        vm.prank(bob);
        kaliCurve.setCurveData(count, data);
    }

    function testCurveWithDaoTreasury_SetCurveMintStatus() public payable {
        testCurveWithDaoTreasury();
        vm.warp(block.timestamp + 100);

        bool status = kaliCurve.getCurveMintStatus(1);

        vm.prank(alice);
        kaliCurve.setCurveMintStatus(1, !status);
        assertEq(kaliCurve.getCurveMintStatus(1), !status);
    }

    function testCurveWithDaoTreasury_SetCurveMintStatus_NotOwner(bool status) public payable {
        testCurveWithDaoTreasury();
        vm.warp(block.timestamp + 100);

        vm.expectRevert(KaliCurve.NotAuthorized.selector);
        vm.prank(bob);
        kaliCurve.setCurveMintStatus(1, status);
    }

    function testCurveWithDaoTreasury_SetCurveTreasury() public payable {
        testCurveWithDaoTreasury();
        vm.warp(block.timestamp + 100);

        bool status = kaliCurve.getCurveTreasury(1);

        vm.prank(alice);
        kaliCurve.setCurveTreasury(1, !status);
        assertEq(kaliCurve.getCurveTreasury(1), !status);
    }

    function testCurveWithDaoTreasury_SetCurveTreasury_NotOwner(bool status) public payable {
        testCurveWithDaoTreasury();
        vm.warp(block.timestamp + 100);

        vm.expectRevert(KaliCurve.NotAuthorized.selector);
        vm.prank(bob);
        kaliCurve.setCurveMintStatus(1, status);
    }

    function testCurveWithDaoTreasury_OwnerZero() public payable {
        initialize(dao, address(factory));

        vm.expectRevert(KaliCurve.NotAuthorized.selector);
        vm.prank(alice);
        kaliCurve.curve(
            CurveType.LINEAR, true, true, address(0), uint96(0.0001 ether), uint16(10), uint48(1), uint48(1), uint48(0)
        );
    }

    /// -----------------------------------------------------------------------
    /// Curve Test - User Treasury
    /// -----------------------------------------------------------------------

    function testCurveWithUserTreasury() public payable {
        initialize(dao, address(factory));

        setupCurve(
            CurveType.LINEAR, true, false, alice, uint96(0.0001 ether), uint16(10), uint48(1), uint48(1), uint48(0)
        );
    }
    /// -----------------------------------------------------------------------
    /// Donate Test
    /// -----------------------------------------------------------------------

    function testDonateWithDaoTreasury_NewUsers() public payable {
        testCurveWithDaoTreasury();
        vm.warp(block.timestamp + 100);

        uint256 count = kaliCurve.getCurveCount();
        uint256 mintPrice = kaliCurve.getPrice(true, kaliCurve.getCurveCount());
        uint256 burnPrice = kaliCurve.getPrice(false, kaliCurve.getCurveCount());
        uint256 diff = kaliCurve.getMintBurnDifference(kaliCurve.getCurveCount());
        assertEq(mintPrice - burnPrice, diff);

        // Bob donates.
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        kaliCurve.donate{value: mintPrice}(count, bob, mintPrice);

        // Validate.
        address impactDao = kaliCurve.getImpactDao(count);
        assertEq(IKaliTokenManager(impactDao).balanceOf(bob), 1 ether);
        assertEq(address(kaliCurve).balance, mintPrice);
        assertEq(kaliCurve.getUnclaimed(impactDao), diff);

        uint256 _mintPrice = kaliCurve.getPrice(true, kaliCurve.getCurveCount());
        uint256 _burnPrice = kaliCurve.getPrice(false, kaliCurve.getCurveCount());
        uint256 _diff = kaliCurve.getMintBurnDifference(kaliCurve.getCurveCount());
        assertEq(_mintPrice - _burnPrice, _diff);

        // Charlie donates.
        vm.deal(charlie, 10 ether);
        vm.prank(charlie);
        kaliCurve.donate{value: _mintPrice}(count, charlie, _mintPrice);

        // Validate.
        assertEq(IKaliTokenManager(impactDao).balanceOf(charlie), 1 ether);
        assertEq(address(kaliCurve).balance, _mintPrice + mintPrice);
        assertEq(kaliCurve.getUnclaimed(impactDao), _diff + diff);
    }

    function testDonateWithDaoTreasury_RecurringUser() public payable {
        testCurveWithDaoTreasury();
        vm.warp(block.timestamp + 100);

        uint256 count = kaliCurve.getCurveCount();
        uint256 mintPrice = kaliCurve.getPrice(true, kaliCurve.getCurveCount());
        uint256 burnPrice = kaliCurve.getPrice(false, kaliCurve.getCurveCount());
        uint256 diff = kaliCurve.getMintBurnDifference(kaliCurve.getCurveCount());
        assertEq(mintPrice - burnPrice, diff);

        // Charlie donates.
        vm.deal(charlie, 10 ether);
        vm.prank(charlie);
        kaliCurve.donate{value: mintPrice}(count, charlie, mintPrice);

        // Validate Charlie as a new patron.
        address impactDao = kaliCurve.getImpactDao(count);
        assertEq(IKaliTokenManager(impactDao).balanceOf(charlie), 1 ether);
        assertEq(address(kaliCurve).balance, mintPrice);
        assertEq(kaliCurve.getUnclaimed(impactDao), diff);
        vm.warp(block.timestamp + 100);

        // Validate next mint price.
        uint256 _mintPrice = kaliCurve.getPrice(true, kaliCurve.getCurveCount());
        uint256 _burnPrice = kaliCurve.getPrice(false, kaliCurve.getCurveCount());
        uint256 _diff = kaliCurve.getMintBurnDifference(kaliCurve.getCurveCount());
        assertEq(_mintPrice - _burnPrice, _diff);

        // Charlie donates again.
        vm.prank(charlie);
        kaliCurve.donate{value: _mintPrice}(count, charlie, _mintPrice);

        // Validate.
        assertEq(IKaliTokenManager(impactDao).balanceOf(charlie), 1 ether);
        assertEq(address(kaliCurve).balance, _mintPrice + mintPrice);
        assertEq(kaliCurve.getUnclaimed(impactDao), diff + _mintPrice);
        // emit log_uint(_mintPrice);
        // emit log_uint(burnPrice);
    }

    function testDonateWithDaoTreasury_NotAuthorized() public payable {
        testCurveWithDaoTreasury();
        vm.warp(block.timestamp + 100);

        uint256 amount = kaliCurve.getPrice(true, kaliCurve.getCurveCount());
        uint256 count = kaliCurve.getCurveCount();

        // Alice tries to donate to her own curve.
        vm.deal(alice, 10 ether);
        vm.expectRevert(KaliCurve.NotAuthorized.selector);
        vm.prank(alice);
        kaliCurve.donate{value: amount}(count, alice, amount);
    }

    function testDonateWithUserTreasury() public payable {
        testCurveWithUserTreasury();
        vm.warp(block.timestamp + 100);

        uint256 amount = kaliCurve.getPrice(true, kaliCurve.getCurveCount());
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
    /// Fuzzy Curve Test
    /// -----------------------------------------------------------------------

    function testFuzzyEncoding(uint96 scale, uint16 ratio, uint48 constant_a, uint48 constant_b, uint48 constant_c)
        public
        payable
    {
        uint256 key = kaliCurve.encodeCurveData(scale, ratio, constant_a, constant_b, constant_c);
        emit log_uint(key);
        emit log_bytes32(bytes32(key));
        (uint256 _scale, uint256 _ratio, uint256 _constant_a, uint256 _constant_b, uint256 _constant_c) =
            kaliCurve.decodeCurveData(key);

        assertEq(_scale, scale);
        assertEq(_ratio, ratio);
        assertEq(_constant_a, constant_a);
        assertEq(_constant_b, constant_b);
        assertEq(_constant_c, constant_c);
    }

    function testCurve_FuzzyDaoTreasury(
        uint96 scale,
        uint16 ratio,
        uint48 constant_a,
        uint48 constant_b,
        uint48 constant_c
    ) public payable {
        vm.assume(ratio <= 100);
        initialize(dao, address(factory));

        setupCurve(CurveType.LINEAR, true, true, alice, scale, ratio, constant_a, constant_b, constant_c);
    }

    function testCurve_FuzzyUserTreasury(
        uint96 scale,
        uint16 ratio,
        uint48 constant_a,
        uint48 constant_b,
        uint48 constant_c
    ) public payable {
        vm.assume(ratio <= 100);
        initialize(dao, address(factory));

        setupCurve(CurveType.LINEAR, true, false, alice, scale, ratio, constant_a, constant_b, constant_c);
    }

    function testCurve_FuzzySetCurveData(
        uint96 scale,
        uint16 ratio,
        uint48 constant_a,
        uint48 constant_b,
        uint48 constant_c
    ) public payable {
        testCurveWithDaoTreasury();
        vm.warp(block.timestamp + 100);

        uint256 count = kaliCurve.getCurveCount();
        uint256 data = kaliCurve.encodeCurveData(scale, ratio, constant_a, constant_b, constant_c);

        vm.prank(alice);
        kaliCurve.setCurveData(count, data);

        (uint256 _scale, uint256 _ratio, uint256 _constant_a, uint256 _constant_b, uint256 _constant_c) =
            kaliCurve.getCurveData(kaliCurve.getCurveCount());
        assertEq(_scale, scale);
        assertEq(_ratio, ratio);
        assertEq(_constant_a, constant_a);
        assertEq(_constant_b, constant_b);
        assertEq(_constant_c, constant_c);
    }

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
        CurveType curveType,
        bool canMint,
        bool daoTreasury,
        address user,
        uint96 scale,
        uint16 burnRatio,
        uint48 constant_a,
        uint48 constant_b,
        uint48 constant_c
    ) internal {
        // Set up curve.
        vm.prank(user);
        kaliCurve.curve(curveType, canMint, daoTreasury, user, scale, burnRatio, constant_a, constant_b, constant_c);

        // Validate.
        uint256 count = kaliCurve.getCurveCount();
        assertEq(count, 1);
        assertEq(kaliCurve.getCurveOwner(count), user);
        assertEq(kaliCurve.getCurveMintStatus(count), canMint);
        assertEq(kaliCurve.getCurveTreasury(count), daoTreasury);
        assertEq(kaliCurve.getCurveSupply(count), 1);
        assertEq(uint256(kaliCurve.getCurveType(count)), uint256(CurveType.LINEAR));
        assertEq(
            kaliCurve.getPrice(true, count),
            price(
                true,
                curveType,
                uint256(scale),
                uint256(kaliCurve.getCurveSupply(count)),
                uint256(burnRatio),
                uint256(constant_a),
                uint256(constant_b),
                uint256(constant_c)
            )
        );
        assertEq(
            kaliCurve.getPrice(false, count),
            price(
                false,
                curveType,
                uint256(scale),
                uint256(kaliCurve.getCurveSupply(count)),
                uint256(burnRatio),
                uint256(constant_a),
                uint256(constant_b),
                uint256(constant_c)
            )
        );
    }

    function price(
        bool mint,
        CurveType curveType,
        uint256 scale,
        uint256 supply,
        uint256 burnRatio,
        uint256 constant_a,
        uint256 constant_b,
        uint256 constant_c
    ) internal returns (uint256) {
        uint256 price;

        supply = mint ? supply + 1 : supply;
        burnRatio = mint ? 100 : uint256(100) - burnRatio;

        if (curveType == CurveType.LINEAR) {
            // Return linear pricing based on, a * b * x + b.
            price = (constant_a * supply * scale + constant_b * scale) * burnRatio / 100;
        } else if (curveType == CurveType.CURVE) {
            // Return curve pricing based on, a * c * x^2 + b * c * x + c.
            price = (constant_a * (supply ** 2) * scale + constant_b * supply * scale + constant_c * scale) * burnRatio
                / 100;
        } else {
            price = 0;
        }

        emit log_uint(price);
        return price;
    }
}
