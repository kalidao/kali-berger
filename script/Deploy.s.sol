// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";

import {KaliBerger} from "src/KaliBerger.sol";

/// @notice A very simple deployment script
contract Deploy is Script {
    /// @notice The main script entrypoint.
    /// @return kaliBerger The deployed contract
    function run() external returns (KaliBerger kaliBerger) {
        uint256 privateKey = vm.envUint("DEV_PRIVATE_KEY");
        address account = vm.addr(privateKey);

        console.log("Account", account);

        vm.startBroadcast(privateKey);
        kaliBerger = new KaliBerger();

        vm.stopBroadcast();
    }
}
