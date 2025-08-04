// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@bananapus/core/script/helpers/CoreDeploymentLib.sol";
import "./helpers/RevnetCoreDeploymentLib.sol";

import {Sphinx} from "@sphinx-labs/contracts/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {REVLoans1_1, IREVLoans} from "./../src/REVLoans1_1.sol";

contract Deploy1_1Script is Script, Sphinx {
    /// @notice tracks the deployment of the core contracts for the chain we are deploying to.
    CoreDeployment core;
    /// @notice tracks the revnet core deployments.
    RevnetCoreDeployment revnet;

    // Revnet Network.
    uint256 FEE_PROJECT_ID = 3;
    bytes32 REVLOANS_SALT = "_REV_LOANS_SALT_";

    address LOANS_OWNER;
    address OPERATOR;
    address TRUSTED_FORWARDER;
    IPermit2 PERMIT2;

    function configureSphinx() public override {
        // TODO: Update to contain revnet devs.
        sphinxConfig.projectName = "revnet-core";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    function run() public {
        // Get the operator address.
        OPERATOR = safeAddress();
        // Get the loans owner address.
        LOANS_OWNER = safeAddress();

        // Get the deployment addresses for the nana CORE for this chain.
        // We want to do this outside of the `sphinx` modifier.
        core = CoreDeploymentLib.getDeployment(
            vm.envOr("NANA_CORE_DEPLOYMENT_PATH", string("node_modules/@bananapus/core/deployments/"))
        );
        revnet = RevnetCoreDeploymentLib.getDeployment(vm.envOr("REVNET_CORE_DEPLOYMENT_PATH", string("deployments/")));

        // We use the same trusted forwarder and permit2 as the core deployment.
        TRUSTED_FORWARDER = core.controller.trustedForwarder();
        PERMIT2 = core.terminal.PERMIT2();

        // Perform the deployment transactions.
        deploy();
    }

    function deploy() public sphinx {
        new REVLoans1_1{salt: REVLOANS_SALT}({
            revnets: revnet.basic_deployer,
            revId: FEE_PROJECT_ID,
            owner: LOANS_OWNER,
            permit2: PERMIT2,
            trustedForwarder: TRUSTED_FORWARDER
        });
    }
}
