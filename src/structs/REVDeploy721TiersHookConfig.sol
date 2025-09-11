// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JBDeploy721TiersHookConfig} from "@bananapus/721-hook-v5/src/structs/JBDeploy721TiersHookConfig.sol";

/// @custom:member baseline721HookConfiguration The baseline config.
/// @custom:member salt The salt to base the collection's address on.
/// @custom:member splitOperatorCanAdjustTiers A flag indicating if the revnet's split operator can add tiers and remove
/// tiers if
/// the tier is allowed to be removed
/// @custom:member splitOperatorCanUpdateMetadata A flag indicating if the revnet's split operator can update the 721's
/// metadata.
/// @custom:member splitOperatorCanMint A flag indicating if the revnet's split operator can mint 721's from tiers that
/// allow it.
/// @custom:member splitOperatorCanIncreaseDiscountPercent A flag indicating if the revnet's split operator can increase
/// the
/// discount of a tier.
struct REVDeploy721TiersHookConfig {
    JBDeploy721TiersHookConfig baseline721HookConfiguration;
    bytes32 salt;
    bool splitOperatorCanAdjustTiers;
    bool splitOperatorCanUpdateMetadata;
    bool splitOperatorCanMint;
    bool splitOperatorCanIncreaseDiscountPercent;
}
