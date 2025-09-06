// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {mulDiv} from "@prb/math/src/Common.sol";
import {IJB721TiersHook} from "@bananapus/721-hook/src/interfaces/IJB721TiersHook.sol";
import {IJB721TiersHookDeployer} from "@bananapus/721-hook/src/interfaces/IJB721TiersHookDeployer.sol";
import {IJBBuybackHook} from "@bananapus/buyback-hook/src/interfaces/IJBBuybackHook.sol";
import {IJBCashOutHook} from "@bananapus/core/src/interfaces/IJBCashOutHook.sol";
import {IJBController} from "@bananapus/core/src/interfaces/IJBController.sol";
import {IJBDirectory} from "@bananapus/core/src/interfaces/IJBDirectory.sol";
import {IJBPayHook} from "@bananapus/core/src/interfaces/IJBPayHook.sol";
import {IJBPermissioned} from "@bananapus/core/src/interfaces/IJBPermissioned.sol";
import {IJBPermissions} from "@bananapus/core/src/interfaces/IJBPermissions.sol";
import {IJBProjects} from "@bananapus/core/src/interfaces/IJBProjects.sol";
import {IJBRulesetApprovalHook} from "@bananapus/core/src/interfaces/IJBRulesetApprovalHook.sol";
import {IJBRulesetDataHook} from "@bananapus/core/src/interfaces/IJBRulesetDataHook.sol";
import {IJBSplitHook} from "@bananapus/core/src/interfaces/IJBSplitHook.sol";
import {IJBTerminal} from "@bananapus/core/src/interfaces/IJBTerminal.sol";
import {JBCashOuts} from "@bananapus/core/src/libraries/JBCashOuts.sol";
import {JBConstants} from "@bananapus/core/src/libraries/JBConstants.sol";
import {JBSplitGroupIds} from "@bananapus/core/src/libraries/JBSplitGroupIds.sol";
import {JBAccountingContext} from "@bananapus/core/src/structs/JBAccountingContext.sol";
import {JBAfterCashOutRecordedContext} from "@bananapus/core/src/structs/JBAfterCashOutRecordedContext.sol";
import {JBBeforePayRecordedContext} from "@bananapus/core/src/structs/JBBeforePayRecordedContext.sol";
import {JBBeforeCashOutRecordedContext} from "@bananapus/core/src/structs/JBBeforeCashOutRecordedContext.sol";
import {JBCurrencyAmount} from "@bananapus/core/src/structs/JBCurrencyAmount.sol";
import {JBFundAccessLimitGroup} from "@bananapus/core/src/structs/JBFundAccessLimitGroup.sol";
import {JBPermissionsData} from "@bananapus/core/src/structs/JBPermissionsData.sol";
import {JBPayHookSpecification} from "@bananapus/core/src/structs/JBPayHookSpecification.sol";
import {JBRulesetConfig} from "@bananapus/core/src/structs/JBRulesetConfig.sol";
import {JBRulesetMetadata} from "@bananapus/core/src/structs/JBRulesetMetadata.sol";
import {JBSplit} from "@bananapus/core/src/structs/JBSplit.sol";
import {JBSplitGroup} from "@bananapus/core/src/structs/JBSplitGroup.sol";
import {JBTerminalConfig} from "@bananapus/core/src/structs/JBTerminalConfig.sol";
import {JBCashOutHookSpecification} from "@bananapus/core/src/structs/JBCashOutHookSpecification.sol";
import {JBPermissionIds} from "@bananapus/permission-ids/src/JBPermissionIds.sol";
import {IJBSuckerRegistry} from "@bananapus/suckers/src/interfaces/IJBSuckerRegistry.sol";
import {CTPublisher} from "@croptop/core/src/CTPublisher.sol";
import {CTAllowedPost} from "@croptop/core/src/structs/CTAllowedPost.sol";

import {IREVDeployer} from "./interfaces/IREVDeployer.sol";
import {REVAutoIssuance} from "./structs/REVAutoIssuance.sol";
import {REVBuybackHookConfig} from "./structs/REVBuybackHookConfig.sol";
import {REVBuybackPoolConfig} from "./structs/REVBuybackPoolConfig.sol";
import {REVConfig} from "./structs/REVConfig.sol";
import {REVCroptopAllowedPost} from "./structs/REVCroptopAllowedPost.sol";
import {REVDeploy721TiersHookConfig} from "./structs/REVDeploy721TiersHookConfig.sol";
import {REVLoanSource} from "./structs/REVLoanSource.sol";
import {REVStageConfig} from "./structs/REVStageConfig.sol";
import {REVSuckerDeploymentConfig} from "./structs/REVSuckerDeploymentConfig.sol";

/// @notice `REVDeployer` deploys, manages, and operates Revnets.
/// @dev Revnets are unowned Juicebox projects which operate autonomously after deployment.
contract REVDeployer is ERC2771Context, IREVDeployer, IJBRulesetDataHook, IJBCashOutHook, IERC721Receiver {
    // A library that adds default safety checks to ERC20 functionality.
    using SafeERC20 for IERC20;

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error REVDeployer_LoanSourceDoesntMatchTerminalConfigurations(address token, address terminal);
    error REVDeployer_AutoIssuanceBeneficiaryZeroAddress();
    error REVDeployer_CashOutDelayNotFinished(uint256 cashOutDelay, uint256 blockTimestamp);
    error REVDeployer_CashOutsCantBeTurnedOffCompletely(uint256 cashOutTaxRate, uint256 maxCashOutTaxRate);
    error REVDeployer_MustHaveSplits();
    error REVDeployer_NothingToAutoIssue();
    error REVDeployer_RulesetDoesNotAllowDeployingSuckers();
    error REVDeployer_StageNotStarted(uint256 stageId);
    error REVDeployer_StagesRequired();
    error REVDeployer_StageTimesMustIncrease();
    error REVDeployer_Unauthorized(uint256 revnetId, address caller);

    //*********************************************************************//
    // ------------------------- public constants ------------------------ //
    //*********************************************************************//

    /// @notice The number of seconds until a revnet's participants can cash out, starting from the time when that
    /// revnet is deployed to a new network.
    /// - Only applies to existing revnets which are deploying onto a new network.
    /// - To prevent liquidity/arbitrage issues which might arise when an existing revnet adds a brand-new treasury.
    /// @dev 30 days, in seconds.
    uint256 public constant override CASH_OUT_DELAY = 2_592_000;

    /// @notice The cash out fee (as a fraction out of `JBConstants.MAX_FEE`).
    /// Cashout fees are paid to the revnet with the `FEE_REVNET_ID`.
    /// @dev Fees are charged on cashouts if the cash out tax rate is greater than 0%.
    /// @dev When suckers withdraw funds, they do not pay cash out fees.
    uint256 public constant override FEE = 25; // 2.5%

    //*********************************************************************//
    // --------------- public immutable stored properties ---------------- //
    //*********************************************************************//

    /// @notice The controller used to create and manage Juicebox projects for revnets.
    IJBController public immutable override CONTROLLER;

    /// @notice The directory of terminals and controllers for Juicebox projects (and revnets).
    IJBDirectory public immutable override DIRECTORY;

    /// @notice The Juicebox project ID of the revnet that receives cash out fees.
    uint256 public immutable override FEE_REVNET_ID;

    /// @notice Deploys tiered ERC-721 hooks for revnets.
    IJB721TiersHookDeployer public immutable override HOOK_DEPLOYER;

    /// @notice Stores Juicebox project (and revnet) access permissions.
    IJBPermissions public immutable override PERMISSIONS;

    /// @notice Mints ERC-721s that represent Juicebox project (and revnet) ownership and transfers.
    IJBProjects public immutable override PROJECTS;

    /// @notice Manages the publishing of ERC-721 posts to revnet's tiered ERC-721 hooks.
    CTPublisher public immutable override PUBLISHER;

    /// @notice Deploys and tracks suckers for revnets.
    IJBSuckerRegistry public immutable override SUCKER_REGISTRY;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The number of revnet tokens which can be "auto-minted" (minted without payments)
    /// for a specific beneficiary during a stage. Think of this as a per-stage premint.
    /// @dev These tokens can be minted with `autoIssueFor(…)`.
    /// @custom:param revnetId The ID of the revnet to get the auto-mint amount for.
    /// @custom:param stageId The ID of the stage to get the auto-mint amount for.
    /// @custom:param beneficiary The beneficiary of the auto-mint.
    mapping(uint256 revnetId => mapping(uint256 stageId => mapping(address beneficiary => uint256))) public override
        amountToAutoIssue;

    /// @notice Each revnet's buyback data hook. These return buyback hook data.
    /// @dev Buyback hooks are a combined data hook/pay hook.
    /// @custom:param revnetId The ID of the revnet to get the buyback data hook for.
    mapping(uint256 revnetId => IJBRulesetDataHook buybackHook) public override buybackHookOf;

    /// @notice The timestamp of when cashouts will become available to a specific revnet's participants.
    /// @dev Only applies to existing revnets which are deploying onto a new network.
    /// @custom:param revnetId The ID of the revnet to get the cash out delay for.
    mapping(uint256 revnetId => uint256 cashOutDelay) public override cashOutDelayOf;

    /// @notice The hashed encoded configuration of each revnet.
    /// @dev This is used to ensure that the encoded configuration of a revnet is the same when deploying suckers for
    /// omnichain operations.
    /// @custom:param revnetId The ID of the revnet to get the hashed encoded configuration for.
    mapping(uint256 revnetId => bytes32 hashedEncodedConfiguration) public override hashedEncodedConfigurationOf;

    /// @notice Each revnet's loan contract.
    /// @dev Revnets can offer loans to their participants, collateralized by their tokens.
    /// Participants can borrow up to the current cash out value of their tokens.
    /// @custom:param revnetId The ID of the revnet to get the loan contract of.
    mapping(uint256 revnetId => address) public override loansOf;

    /// @notice Each revnet's tiered ERC-721 hook.
    /// @custom:param revnetId The ID of the revnet to get the tiered ERC-721 hook for.
    // slither-disable-next-line uninitialized-state
    mapping(uint256 revnetId => IJB721TiersHook tiered721Hook) public override tiered721HookOf;

    //*********************************************************************//
    // ------------------- internal stored properties -------------------- //
    //*********************************************************************//

    /// @notice A list of `JBPermissonIds` indices to grant to the split operator of a specific revnet.
    /// @dev These should be set in the revnet's deployment process.
    /// @custom:param revnetId The ID of the revnet to get the extra operator permissions for.
    // slither-disable-next-line uninitialized-state
    mapping(uint256 revnetId => uint256[]) internal _extraOperatorPermissions;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    /// @param controller The controller to use for launching and operating the Juicebox projects which will be revnets.
    /// @param suckerRegistry The registry to use for deploying and tracking each revnet's suckers.
    /// @param feeRevnetId The Juicebox project ID of the revnet that will receive fees.
    /// @param hookDeployer The deployer to use for revnet's tiered ERC-721 hooks.
    /// @param publisher The croptop publisher revnets can use to publish ERC-721 posts to their tiered ERC-721 hooks.
    /// @param trustedForwarder The trusted forwarder for the ERC2771Context.
    constructor(
        IJBController controller,
        IJBSuckerRegistry suckerRegistry,
        uint256 feeRevnetId,
        IJB721TiersHookDeployer hookDeployer,
        CTPublisher publisher,
        address trustedForwarder
    )
        ERC2771Context(trustedForwarder)
    {
        CONTROLLER = controller;
        DIRECTORY = controller.DIRECTORY();
        PROJECTS = controller.PROJECTS();
        PERMISSIONS = IJBPermissioned(address(CONTROLLER)).PERMISSIONS();
        SUCKER_REGISTRY = suckerRegistry;
        FEE_REVNET_ID = feeRevnetId;
        HOOK_DEPLOYER = hookDeployer;
        PUBLISHER = publisher;

        // Give the sucker registry permission to map tokens for all revnets.
        _setPermission({operator: address(SUCKER_REGISTRY), revnetId: 0, permissionId: JBPermissionIds.MAP_SUCKER_TOKEN});
    }

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Before a revnet processes an incoming payment, determine the weight and pay hooks to use.
    /// @dev This function is part of `IJBRulesetDataHook`, and gets called before the revnet processes a payment.
    /// @param context Standard Juicebox payment context. See `JBBeforePayRecordedContext`.
    /// @return weight The weight which revnet tokens are minted relative to. This can be used to customize how many
    /// tokens get minted by a payment.
    /// @return hookSpecifications Amounts (out of what's being paid in) to be sent to pay hooks instead of being paid
    /// into the revnet. Useful for automatically routing funds from a treasury as payments come in.
    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        external
        view
        override
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        // Keep a reference to the specifications provided by the buyback data hook.
        JBPayHookSpecification[] memory buybackHookSpecifications;

        // Keep a reference to the revnet's buyback data hook.
        IJBRulesetDataHook buybackHook = buybackHookOf[context.projectId];

        // Read the weight and specifications from the buyback data hook.
        // If there's no buyback data hook, use the default weight.
        if (buybackHook != IJBRulesetDataHook(address(0))) {
            (weight, buybackHookSpecifications) = buybackHook.beforePayRecordedWith(context);
        } else {
            weight = context.weight;
        }

        // Is there a buyback hook specification?
        bool usesBuybackHook = buybackHookSpecifications.length == 1;

        // Keep a reference to the revnet's tiered ERC-721 hook.
        IJB721TiersHook tiered721Hook = tiered721HookOf[context.projectId];

        // Is there a tiered ERC-721 hook?
        bool usesTiered721Hook = address(tiered721Hook) != address(0);

        // Initialize the returned specification array with enough room to include the specifications we're using.
        hookSpecifications = new JBPayHookSpecification[]((usesTiered721Hook ? 1 : 0) + (usesBuybackHook ? 1 : 0));

        // If we have a tiered ERC-721 hook, add it to the array.
        if (usesTiered721Hook) {
            hookSpecifications[0] =
                JBPayHookSpecification({hook: IJBPayHook(address(tiered721Hook)), amount: 0, metadata: bytes("")});
        }

        // If we have a buyback hook specification, add it to the end of the array.
        if (usesBuybackHook) hookSpecifications[1] = buybackHookSpecifications[0];
    }

    /// @notice Determine how a cash out from a revnet should be processed.
    /// @dev This function is part of `IJBRulesetDataHook`, and gets called before the revnet processes a cash out.
    /// @dev If a sucker is cashing out, no taxes or fees are imposed.
    /// @param context Standard Juicebox cash out context. See `JBBeforeCashOutRecordedContext`.
    /// @return cashOutTaxRate The cash out tax rate, which influences the amount of terminal tokens which get cashed
    /// out.
    /// @return cashOutCount The number of revnet tokens that are cashed out.
    /// @return totalSupply The total revnet token supply.
    /// @return hookSpecifications The amount of funds and the data to send to cash out hooks (this contract).
    function beforeCashOutRecordedWith(JBBeforeCashOutRecordedContext calldata context)
        external
        view
        override
        returns (
            uint256 cashOutTaxRate,
            uint256 cashOutCount,
            uint256 totalSupply,
            JBCashOutHookSpecification[] memory hookSpecifications
        )
    {
        // If the cash out is from a sucker, return the full cash out amount without taxes or fees.
        if (_isSuckerOf({revnetId: context.projectId, addr: context.holder})) {
            return (0, context.cashOutCount, context.totalSupply, hookSpecifications);
        }

        // Keep a reference to the cash out delay of the revnet.
        uint256 cashOutDelay = cashOutDelayOf[context.projectId];

        // Enforce the cash out delay.
        if (cashOutDelay > block.timestamp) {
            revert REVDeployer_CashOutDelayNotFinished(cashOutDelay, block.timestamp);
        }

        // Get the terminal that will receive the cash out fee.
        IJBTerminal feeTerminal = DIRECTORY.primaryTerminalOf(FEE_REVNET_ID, context.surplus.token);

        // If there's no cash out tax (100% cash out tax rate), or if there's no fee terminal, do not charge a fee.
        if (context.cashOutTaxRate == 0 || address(feeTerminal) == address(0)) {
            return (context.cashOutTaxRate, context.cashOutCount, context.totalSupply, hookSpecifications);
        }

        // Get a reference to the number of tokens being used to pay the fee (out of the total being cashed out).
        uint256 feeCashOutCount = mulDiv(context.cashOutCount, FEE, JBConstants.MAX_FEE);
        uint256 nonFeeCashOutCount = context.cashOutCount - feeCashOutCount;

        // Keep a reference to the amount claimable with non-fee tokens.
        uint256 postFeeReclaimedAmount = JBCashOuts.cashOutFrom({
            surplus: context.surplus.value,
            cashOutCount: nonFeeCashOutCount,
            totalSupply: context.totalSupply,
            cashOutTaxRate: context.cashOutTaxRate
        });

        // Keep a reference to the fee amount after the reclaimed amount is subtracted.
        uint256 feeAmount = JBCashOuts.cashOutFrom({
            surplus: context.surplus.value - postFeeReclaimedAmount,
            cashOutCount: feeCashOutCount,
            totalSupply: context.totalSupply - nonFeeCashOutCount,
            cashOutTaxRate: context.cashOutTaxRate
        });

        // Assemble a cash out hook specification to invoke `afterCashOutRecordedWith(…)` with, to process the fee.
        hookSpecifications = new JBCashOutHookSpecification[](1);
        hookSpecifications[0] = JBCashOutHookSpecification({
            hook: IJBCashOutHook(address(this)),
            amount: feeAmount,
            metadata: abi.encode(feeTerminal)
        });

        // Return the cash out rate and the number of revnet tokens to cash out, minus the tokens being used to pay the
        // fee.
        return (context.cashOutTaxRate, nonFeeCashOutCount, context.totalSupply, hookSpecifications);
    }

    /// @notice A flag indicating whether an address has permission to mint a revnet's tokens on-demand.
    /// @dev Required by the `IJBRulesetDataHook` interface.
    /// @param revnetId The ID of the revnet to check permissions for.
    /// @param addr The address to check the mint permission of.
    /// @return flag A flag indicating whether the address has permission to mint the revnet's tokens on-demand.
    function hasMintPermissionFor(uint256 revnetId, address addr) external view override returns (bool) {
        IJBRulesetDataHook buybackHook = buybackHookOf[revnetId];
        // The buyback hook, loans contract, and suckers are allowed to mint the revnet's tokens.
        return addr == address(buybackHook) || buybackHook.hasMintPermissionFor(revnetId, addr) || addr == loansOf[revnetId]
            || _isSuckerOf({revnetId: revnetId, addr: addr});
    }

    /// @dev Make sure this contract can only receive project NFTs from `JBProjects`.
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        // Make sure the 721 received is from the `JBProjects` contract.
        if (msg.sender != address(PROJECTS)) revert();

        return IERC721Receiver.onERC721Received.selector;
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    /// @notice A flag indicating whether an address is a revnet's split operator.
    /// @param revnetId The ID of the revnet.
    /// @param addr The address to check.
    /// @return flag A flag indicating whether the address is the revnet's split operator.
    function isSplitOperatorOf(uint256 revnetId, address addr) public view override returns (bool) {
        return PERMISSIONS.hasPermissions({
            operator: addr,
            account: address(this),
            projectId: revnetId,
            permissionIds: _splitOperatorPermissionIndexesOf(revnetId),
            includeRoot: false,
            includeWildcardProjectId: false
        });
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See `IERC165.supportsInterface`.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IREVDeployer).interfaceId || interfaceId == type(IJBRulesetDataHook).interfaceId
            || interfaceId == type(IJBCashOutHook).interfaceId || interfaceId == type(IERC721Receiver).interfaceId;
    }

    //*********************************************************************//
    // -------------------------- internal views ------------------------- //
    //*********************************************************************//

    /// @notice If the specified address is not the revnet's current split operator, revert.
    /// @param revnetId The ID of the revnet to check split operator status for.
    /// @param operator The address being checked.
    function _checkIfIsSplitOperatorOf(uint256 revnetId, address operator) internal view {
        if (!isSplitOperatorOf(revnetId, operator)) revert REVDeployer_Unauthorized(revnetId, operator);
    }

    /// @notice A flag indicating whether an address is a revnet's sucker.
    /// @param revnetId The ID of the revnet to check sucker status for.
    /// @param addr The address being checked.
    /// @return isSucker A flag indicating whether the address is one of the revnet's suckers.
    function _isSuckerOf(uint256 revnetId, address addr) internal view returns (bool) {
        return SUCKER_REGISTRY.isSuckerOf(revnetId, addr);
    }

    /// @notice Initialize a fund access limit group for the loan contract to use.
    /// @dev Returns an unlimited surplus allowance for each token which can be loaned out.
    /// @param configuration The revnet's configuration.
    /// @param terminalConfigurations The terminals to set up for the revnet. Used for payments and cash outs.
    /// @return fundAccessLimitGroups The fund access limit groups for the loans.
    function _makeLoanFundAccessLimits(
        REVConfig calldata configuration,
        JBTerminalConfig[] calldata terminalConfigurations
    )
        internal
        pure
        returns (JBFundAccessLimitGroup[] memory fundAccessLimitGroups)
    {
        // Initialize the fund access limit groups.
        fundAccessLimitGroups = new JBFundAccessLimitGroup[](configuration.loanSources.length);

        // Set up the fund access limits for the loans.
        for (uint256 i; i < configuration.loanSources.length; i++) {
            // Set the loan source being iterated on.
            REVLoanSource calldata loanSource = configuration.loanSources[i];

            // Keep a reference to the currency of the loan source.
            uint32 currency =
                _matchingCurrencyOf({terminalConfigurations: terminalConfigurations, loanSource: loanSource});

            // If the currency is 0 it means the loan source doesn't match the terminal configurations.
            if (currency == 0) {
                revert REVDeployer_LoanSourceDoesntMatchTerminalConfigurations(
                    loanSource.token, address(loanSource.terminal)
                );
            }

            // Set up an unlimited allowance for the loan contract to use.
            JBCurrencyAmount[] memory loanAllowances = new JBCurrencyAmount[](1);
            loanAllowances[0] = JBCurrencyAmount({currency: currency, amount: type(uint224).max});

            // Set up the fund access limits for the loans.
            fundAccessLimitGroups[i] = JBFundAccessLimitGroup({
                terminal: address(loanSource.terminal),
                token: loanSource.token,
                payoutLimits: new JBCurrencyAmount[](0),
                surplusAllowances: loanAllowances
            });
        }
    }

    /// @notice Make a ruleset configuration for a revnet's stage.
    /// @param baseCurrency The base currency of the revnet.
    /// @param stageConfiguration The stage configuration to make a ruleset for.
    /// @param fundAccessLimitGroups The fund access limit groups to set up for the ruleset.
    /// @return rulesetConfiguration The ruleset configuration.
    function _makeRulesetConfiguration(
        uint32 baseCurrency,
        REVStageConfig calldata stageConfiguration,
        JBFundAccessLimitGroup[] memory fundAccessLimitGroups
    )
        internal
        view
        returns (JBRulesetConfig memory)
    {
        // Set up the ruleset's metadata.
        JBRulesetMetadata memory metadata;
        metadata.reservedPercent = stageConfiguration.splitPercent;
        metadata.cashOutTaxRate = stageConfiguration.cashOutTaxRate;
        metadata.baseCurrency = baseCurrency;
        metadata.useTotalSurplusForCashOuts = true; // Use surplus from all terminals for cash outs.
        metadata.allowOwnerMinting = true; // Allow this contract to auto-mint tokens as the revnet's owner.
        metadata.useDataHookForPay = true; // Call this contract's `beforePayRecordedWith(…)` callback on payments.
        metadata.useDataHookForCashOut = true; // Call this contract's `beforeCashOutRecordedWith(…)` callback on cash
            // outs.
        metadata.dataHook = address(this); // This contract is the data hook.
        metadata.metadata = stageConfiguration.extraMetadata;

        // Package the reserved token splits.
        JBSplitGroup[] memory splitGroups = new JBSplitGroup[](1);
        splitGroups[0] = JBSplitGroup({groupId: JBSplitGroupIds.RESERVED_TOKENS, splits: stageConfiguration.splits});

        return JBRulesetConfig({
            mustStartAtOrAfter: stageConfiguration.startsAtOrAfter,
            duration: stageConfiguration.issuanceCutFrequency,
            weight: stageConfiguration.initialIssuance,
            weightCutPercent: stageConfiguration.issuanceCutPercent,
            approvalHook: IJBRulesetApprovalHook(address(0)),
            metadata: metadata,
            splitGroups: splitGroups,
            fundAccessLimitGroups: fundAccessLimitGroups
        });
    }

    /// @notice Returns the currency of the loan source, if a matching terminal configuration is found.
    /// @param terminalConfigurations The terminals to check.
    /// @param loanSource The loan source to check.
    /// @return currency The currency of the loan source.
    function _matchingCurrencyOf(
        JBTerminalConfig[] calldata terminalConfigurations,
        REVLoanSource calldata loanSource
    )
        internal
        pure
        returns (uint32)
    {
        for (uint256 i; i < terminalConfigurations.length; i++) {
            JBTerminalConfig calldata terminalConfiguration = terminalConfigurations[i];
            if (terminalConfiguration.terminal == loanSource.terminal) {
                for (uint256 j; j < terminalConfiguration.accountingContextsToAccept.length; j++) {
                    JBAccountingContext calldata accountingContext = terminalConfiguration.accountingContextsToAccept[j];
                    if (accountingContext.token == loanSource.token) {
                        return accountingContext.currency;
                    }
                }
            }
        }

        // No currency found for the terminal and token combination.
        return 0;
    }

    /// @notice Returns the permissions that the split operator should be granted for a revnet.
    /// @param revnetId The ID of the revnet to get split operator permissions for.
    /// @return allOperatorPermissions The permissions that the split operator should be granted for the revnet,
    /// including both default and custom permissions.
    function _splitOperatorPermissionIndexesOf(uint256 revnetId)
        internal
        view
        returns (uint256[] memory allOperatorPermissions)
    {
        // Keep a reference to the custom split operator permissions.
        uint256[] memory customSplitOperatorPermissionIndexes = _extraOperatorPermissions[revnetId];

        // Make the array that merges the default and custom operator permissions.
        allOperatorPermissions = new uint256[](5 + customSplitOperatorPermissionIndexes.length);
        allOperatorPermissions[0] = JBPermissionIds.SET_SPLIT_GROUPS;
        allOperatorPermissions[1] = JBPermissionIds.SET_BUYBACK_POOL;
        allOperatorPermissions[2] = JBPermissionIds.SET_PROJECT_URI;
        allOperatorPermissions[3] = JBPermissionIds.ADD_PRICE_FEED;
        allOperatorPermissions[4] = JBPermissionIds.SUCKER_SAFETY;

        // Copy the custom permissions into the array.
        for (uint256 i; i < customSplitOperatorPermissionIndexes.length; i++) {
            allOperatorPermissions[5 + i] = customSplitOperatorPermissionIndexes[i];
        }
    }

    //*********************************************************************//
    // --------------------- external transactions ----------------------- //
    //*********************************************************************//

    /// @notice Processes the fee from a cash out.
    /// @param context Cash out context passed in by the terminal.
    function afterCashOutRecordedWith(JBAfterCashOutRecordedContext calldata context) external payable {
        // If there's sufficient approval, transfer normally.
        if (context.forwardedAmount.token != JBConstants.NATIVE_TOKEN) {
            IERC20(context.forwardedAmount.token).safeTransferFrom({
                from: msg.sender,
                to: address(this),
                value: context.forwardedAmount.value
            });
        }

        // Parse the metadata forwarded from the data hook to get the fee terminal.
        // See `beforeCashOutRecordedWith(…)`.
        (IJBTerminal feeTerminal) = abi.decode(context.hookMetadata, (IJBTerminal));

        // Determine how much to pay in `msg.value` (in the native currency).
        uint256 payValue = _beforeTransferTo({
            to: address(feeTerminal),
            token: context.forwardedAmount.token,
            amount: context.forwardedAmount.value
        });

        // Pay the fee.
        // slither-disable-next-line arbitrary-send-eth,unused-return
        try feeTerminal.pay{value: payValue}({
            projectId: FEE_REVNET_ID,
            token: context.forwardedAmount.token,
            amount: context.forwardedAmount.value,
            beneficiary: context.holder,
            minReturnedTokens: 0,
            memo: "",
            metadata: bytes(abi.encodePacked(context.projectId))
        }) {} catch (bytes memory) {
            // Decrease the allowance for the fee terminal if the token is not the native token.
            if (context.forwardedAmount.token != JBConstants.NATIVE_TOKEN) {
                IERC20(context.forwardedAmount.token).safeDecreaseAllowance({
                    spender: address(feeTerminal),
                    requestedDecrease: context.forwardedAmount.value
                });
            }

            // If the fee can't be processed, return the funds to the project.
            payValue = _beforeTransferTo({
                to: msg.sender,
                token: context.forwardedAmount.token,
                amount: context.forwardedAmount.value
            });

            // slither-disable-next-line arbitrary-send-eth
            IJBTerminal(msg.sender).addToBalanceOf{value: payValue}({
                projectId: context.projectId,
                token: context.forwardedAmount.token,
                amount: context.forwardedAmount.value,
                shouldReturnHeldFees: false,
                memo: "",
                metadata: bytes(abi.encodePacked(FEE_REVNET_ID))
            });
        }
    }

    /// @notice Auto-mint a revnet's tokens from a stage for a beneficiary.
    /// @param revnetId The ID of the revnet to auto-mint tokens from.
    /// @param stageId The ID of the stage auto-mint tokens are available from.
    /// @param beneficiary The address to auto-mint tokens to.
    function autoIssueFor(uint256 revnetId, uint256 stageId, address beneficiary) external override {
        // Make sure the stage has started.
        if (CONTROLLER.RULESETS().getRulesetOf(revnetId, stageId).start > block.timestamp) {
            revert REVDeployer_StageNotStarted(stageId);
        }

        // Get a reference to the number of tokens to auto-issue.
        uint256 count = amountToAutoIssue[revnetId][stageId][beneficiary];

        // If there's nothing to auto-mint, return.
        if (count == 0) revert REVDeployer_NothingToAutoIssue();

        // Reset the auto-mint amount.
        amountToAutoIssue[revnetId][stageId][beneficiary] = 0;

        emit AutoIssue({
            revnetId: revnetId,
            stageId: stageId,
            beneficiary: beneficiary,
            count: count,
            caller: _msgSender()
        });

        // Mint the tokens.
        // slither-disable-next-line unused-return
        CONTROLLER.mintTokensOf({
            projectId: revnetId,
            tokenCount: count,
            beneficiary: beneficiary,
            memo: "",
            useReservedPercent: false
        });
    }

    /// @notice Launch a revnet, or convert an existing Juicebox project into a revnet.
    /// @param revnetId The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.
    /// @param configuration Core revnet configuration. See `REVConfig`.
    /// @param terminalConfigurations The terminals to set up for the revnet. Used for payments and cash outs.
    /// @param buybackHookConfiguration The buyback hook and pools to set up for the revnet.
    /// The buyback hook buys tokens from a Uniswap pool if minting new tokens would be more expensive.
    /// @param suckerDeploymentConfiguration The suckers to set up for the revnet. Suckers facilitate cross-chain
    /// token transfers between peer revnets on different networks.
    /// @return revnetId The ID of the newly created revnet.
    function deployFor(
        uint256 revnetId,
        REVConfig calldata configuration,
        JBTerminalConfig[] calldata terminalConfigurations,
        REVBuybackHookConfig calldata buybackHookConfiguration,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        external
        override
        returns (uint256)
    {
        // Keep a reference to the revnet ID which was passed in.
        bool shouldDeployNewRevnet = revnetId == 0;

        // If the caller is deploying a new revnet, calculate its ID
        // (which will be 1 greater than the current count).
        if (shouldDeployNewRevnet) revnetId = PROJECTS.count() + 1;

        // Normalize and encode the configurations.
        (JBRulesetConfig[] memory rulesetConfigurations, bytes32 encodedConfigurationHash) = _makeRulesetConfigurations({
            revnetId: revnetId,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations
        });

        // Deploy the revnet.
        _deployRevnetFor({
            revnetId: revnetId,
            shouldDeployNewRevnet: shouldDeployNewRevnet,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration,
            rulesetConfigurations: rulesetConfigurations,
            encodedConfigurationHash: encodedConfigurationHash
        });

        return revnetId;
    }

    /// @notice Deploy new suckers for an existing revnet.
    /// @dev Only the revnet's split operator can deploy new suckers.
    /// @param revnetId The ID of the revnet to deploy suckers for.
    /// See `_makeRulesetConfigurations(…)` for encoding details. Clients can read the encoded configuration
    /// from the `DeployRevnet` event emitted by this contract.
    /// @param suckerDeploymentConfiguration The suckers to set up for the revnet.
    function deploySuckersFor(
        uint256 revnetId,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        external
        override
        returns (address[] memory suckers)
    {
        // Make sure the caller is the revnet's split operator.
        _checkIfIsSplitOperatorOf({revnetId: revnetId, operator: _msgSender()});

        // Check if the current ruleset allows deploying new suckers.
        // slither-disable-next-line unused-return
        (, JBRulesetMetadata memory metadata) = CONTROLLER.currentRulesetOf(revnetId);

        // Check the third bit, it indicates if the ruleset allows new suckers to be deployed.
        bool allowsDeployingSuckers = ((metadata.metadata >> 2) & 1) == 1;

        if (!allowsDeployingSuckers) {
            revert REVDeployer_RulesetDoesNotAllowDeployingSuckers();
        }

        // Deploy the suckers.
        suckers = _deploySuckersFor({
            revnetId: revnetId,
            encodedConfigurationHash: hashedEncodedConfigurationOf[revnetId],
            suckerDeploymentConfiguration: suckerDeploymentConfiguration
        });
    }

    /// @notice Launch a revnet which sells tiered ERC-721s and (optionally) allows croptop posts to its ERC-721 tiers.
    /// @param revnetId The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.
    /// @param configuration Core revnet configuration. See `REVConfig`.
    /// @param terminalConfigurations The terminals to set up for the revnet. Used for payments and cash outs.
    /// @param buybackHookConfiguration The buyback hook and pools to set up for the revnet.
    /// The buyback hook buys tokens from a Uniswap pool if minting new tokens would be more expensive.
    /// @param suckerDeploymentConfiguration The suckers to set up for the revnet. Suckers facilitate cross-chain
    /// token transfers between peer revnets on different networks.
    /// @param tiered721HookConfiguration How to set up the tiered ERC-721 hook for the revnet.
    /// @param allowedPosts Restrictions on which croptop posts are allowed on the revnet's ERC-721 tiers.
    /// @return revnetId The ID of the newly created revnet.
    /// @return hook The address of the tiered ERC-721 hook that was deployed for the revnet.
    function deployWith721sFor(
        uint256 revnetId,
        REVConfig calldata configuration,
        JBTerminalConfig[] calldata terminalConfigurations,
        REVBuybackHookConfig calldata buybackHookConfiguration,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration,
        REVDeploy721TiersHookConfig calldata tiered721HookConfiguration,
        REVCroptopAllowedPost[] calldata allowedPosts
    )
        external
        override
        returns (uint256, IJB721TiersHook hook)
    {
        // Keep a reference to the revnet ID which was passed in.
        bool shouldDeployNewRevnet = revnetId == 0;

        // If the caller is deploying a new revnet, calculate its ID
        // (which will be 1 greater than the current count).
        if (shouldDeployNewRevnet) revnetId = PROJECTS.count() + 1;

        // Deploy the revnet with the specified tiered ERC-721 hook and croptop posting criteria.
        hook = _deploy721RevnetFor({
            revnetId: revnetId,
            shouldDeployNewRevnet: shouldDeployNewRevnet,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration,
            tiered721HookConfiguration: tiered721HookConfiguration,
            allowedPosts: allowedPosts
        });

        return (revnetId, hook);
    }

    /// @notice Change a revnet's split operator.
    /// @dev Only a revnet's current split operator can set a new split operator.
    /// @param revnetId The ID of the revnet to set the split operator of.
    /// @param newSplitOperator The new split operator's address.
    function setSplitOperatorOf(uint256 revnetId, address newSplitOperator) external override {
        // Enforce permissions.
        _checkIfIsSplitOperatorOf({revnetId: revnetId, operator: _msgSender()});

        emit ReplaceSplitOperator({revnetId: revnetId, newSplitOperator: newSplitOperator, caller: _msgSender()});

        // Remove operator permissions from the old split operator.
        _setPermissionsFor({
            account: address(this),
            operator: _msgSender(),
            revnetId: revnetId,
            permissionIds: new uint8[](0)
        });

        // Set the new split operator.
        _setSplitOperatorOf({revnetId: revnetId, operator: newSplitOperator});
    }

    //*********************************************************************//
    // --------------------- internal transactions ----------------------- //
    //*********************************************************************//

    /// @notice Logic to be triggered before transferring tokens from this contract.
    /// @param to The address the transfer is going to.
    /// @param token The token being transferred.
    /// @param amount The number of tokens being transferred, as a fixed point number with the same number of decimals
    /// as the token specifies.
    /// @return payValue The value to attach to the transaction being sent.
    function _beforeTransferTo(address to, address token, uint256 amount) internal returns (uint256) {
        // If the token is the native token, no allowance needed.
        if (token == JBConstants.NATIVE_TOKEN) return amount;
        IERC20(token).safeIncreaseAllowance(to, amount);
        return 0;
    }

    /// @notice Deploy a revnet which sells tiered ERC-721s and (optionally) allows croptop posts to its ERC-721 tiers.
    /// @param revnetId The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.
    /// @param shouldDeployNewRevnet Whether to deploy a new revnet or convert an existing Juicebox project into a
    /// revnet.
    /// @param configuration Core revnet configuration. See `REVConfig`.
    /// @param terminalConfigurations The terminals to set up for the revnet. Used for payments and cash outs.
    /// @param buybackHookConfiguration The buyback hook and pools to set up for the revnet.
    /// The buyback hook buys tokens from a Uniswap pool if minting new tokens would be more expensive.
    /// @param suckerDeploymentConfiguration The suckers to set up for the revnet. Suckers facilitate cross-chain
    /// token transfers between peer revnets on different networks.
    /// @param tiered721HookConfiguration How to set up the tiered ERC-721 hook for the revnet.
    /// @param allowedPosts Restrictions on which croptop posts are allowed on the revnet's ERC-721 tiers.
    /// @return hook The address of the tiered ERC-721 hook that was deployed for the revnet.
    function _deploy721RevnetFor(
        uint256 revnetId,
        bool shouldDeployNewRevnet,
        REVConfig calldata configuration,
        JBTerminalConfig[] calldata terminalConfigurations,
        REVBuybackHookConfig calldata buybackHookConfiguration,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration,
        REVDeploy721TiersHookConfig calldata tiered721HookConfiguration,
        REVCroptopAllowedPost[] calldata allowedPosts
    )
        internal
        returns (IJB721TiersHook hook)
    {
        // Normalize and encode the configurations.
        (JBRulesetConfig[] memory rulesetConfigurations, bytes32 encodedConfigurationHash) = _makeRulesetConfigurations({
            revnetId: revnetId,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations
        });

        // Deploy the tiered ERC-721 hook contract.
        // slither-disable-next-line reentrancy-benign
        hook = HOOK_DEPLOYER.deployHookFor({
            projectId: revnetId,
            deployTiersHookConfig: tiered721HookConfiguration.baseline721HookConfiguration,
            salt: keccak256(abi.encode(tiered721HookConfiguration.salt, encodedConfigurationHash, _msgSender()))
        });

        // Store the tiered ERC-721 hook.
        tiered721HookOf[revnetId] = hook;

        // If specified, give the split operator permission to add and remove tiers.
        if (tiered721HookConfiguration.splitOperatorCanAdjustTiers) {
            _extraOperatorPermissions[revnetId].push(JBPermissionIds.ADJUST_721_TIERS);
        }

        // If specified, give the split operator permission to set ERC-721 tier metadata.
        if (tiered721HookConfiguration.splitOperatorCanUpdateMetadata) {
            _extraOperatorPermissions[revnetId].push(JBPermissionIds.SET_721_METADATA);
        }

        // If specified, give the split operator permission to mint ERC-721s (without a payment)
        // from tiers with `allowOwnerMint` set to true.
        if (tiered721HookConfiguration.splitOperatorCanMint) {
            _extraOperatorPermissions[revnetId].push(JBPermissionIds.MINT_721);
        }

        // If specified, give the split operator permission to increase the discount of a tier.
        if (tiered721HookConfiguration.splitOperatorCanIncreaseDiscountPercent) {
            _extraOperatorPermissions[revnetId].push(JBPermissionIds.SET_721_DISCOUNT_PERCENT);
        }

        // If there are posts to allow, configure them.
        if (allowedPosts.length != 0) {
            // Keep a reference to the formatted allowed posts.
            CTAllowedPost[] memory formattedAllowedPosts = new CTAllowedPost[](allowedPosts.length);

            // Iterate through each post to add it to the formatted list.
            for (uint256 i; i < allowedPosts.length; i++) {
                // Set the post being iterated on.
                REVCroptopAllowedPost calldata post = allowedPosts[i];

                // Set the formatted post.
                formattedAllowedPosts[i] = CTAllowedPost({
                    hook: address(hook),
                    category: post.category,
                    minimumPrice: post.minimumPrice,
                    minimumTotalSupply: post.minimumTotalSupply,
                    maximumTotalSupply: post.maximumTotalSupply,
                    allowedAddresses: post.allowedAddresses
                });
            }

            // Set up the allowed posts in the publisher.
            PUBLISHER.configurePostingCriteriaFor({allowedPosts: formattedAllowedPosts});

            // Give the croptop publisher permission to post new ERC-721 tiers on this contract's behalf.
            _setPermission({
                operator: address(PUBLISHER),
                revnetId: revnetId,
                permissionId: JBPermissionIds.ADJUST_721_TIERS
            });
        }

        _deployRevnetFor({
            revnetId: revnetId,
            shouldDeployNewRevnet: shouldDeployNewRevnet,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration,
            rulesetConfigurations: rulesetConfigurations,
            encodedConfigurationHash: encodedConfigurationHash
        });
    }

    /// @notice Deploy a revnet, or convert an existing Juicebox project into a revnet.
    /// @param revnetId The ID of the Juicebox project to turn into a revnet. Send 0 to deploy a new revnet.
    /// @param shouldDeployNewRevnet Whether to deploy a new revnet or convert an existing Juicebox project into a
    /// revnet.
    /// @param configuration Core revnet configuration. See `REVConfig`.
    /// @param terminalConfigurations The terminals to set up for the revnet. Used for payments and cash outs.
    /// @param buybackHookConfiguration The buyback hook and pools to set up for the revnet.
    /// The buyback hook buys tokens from a Uniswap pool if minting new tokens would be more expensive.
    /// @param suckerDeploymentConfiguration The suckers to set up for the revnet. Suckers facilitate cross-chain
    /// token transfers between peer revnets on different networks.
    /// @param rulesetConfigurations The rulesets to set up for the revnet.
    /// @param encodedConfigurationHash A hash that represents the revnet's configuration.
    /// See `_makeRulesetConfigurations(…)` for encoding details. Clients can read the encoded configuration
    /// from the `DeployRevnet` event emitted by this contract.
    function _deployRevnetFor(
        uint256 revnetId,
        bool shouldDeployNewRevnet,
        REVConfig calldata configuration,
        JBTerminalConfig[] calldata terminalConfigurations,
        REVBuybackHookConfig calldata buybackHookConfiguration,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration,
        JBRulesetConfig[] memory rulesetConfigurations,
        bytes32 encodedConfigurationHash
    )
        internal
    {
        if (shouldDeployNewRevnet) {
            // If we're deploying a new revnet, launch a Juicebox project for it.
            // Sanity check that we deployed the `revnetId` that we expected to deploy.
            // slither-disable-next-line reentrancy-benign,reentrancy-events
            assert(
                CONTROLLER.launchProjectFor({
                    owner: address(this),
                    projectUri: configuration.description.uri,
                    rulesetConfigurations: rulesetConfigurations,
                    terminalConfigurations: terminalConfigurations,
                    memo: ""
                }) == revnetId
            );
        } else {
            // Keep a reference to the Juicebox project's owner.
            address owner = PROJECTS.ownerOf(revnetId);

            // Make sure the caller is the owner of the Juicebox project.
            if (_msgSender() != owner) revert REVDeployer_Unauthorized(revnetId, _msgSender());

            // If we're converting an existing Juicebox project into a revnet,
            // transfer the `JBProjects` NFT to this deployer.
            IERC721(PROJECTS).safeTransferFrom({from: owner, to: address(this), tokenId: revnetId});

            // Launch the revnet rulesets for the pre-existing project.
            // slither-disable-next-line unused-return
            CONTROLLER.launchRulesetsFor({
                projectId: revnetId,
                rulesetConfigurations: rulesetConfigurations,
                terminalConfigurations: terminalConfigurations,
                memo: ""
            });

            // Set the revnet's URI.
            CONTROLLER.setUriOf({projectId: revnetId, uri: configuration.description.uri});
        }

        // Store the cash out delay of the revnet if its stages are already in progress.
        // This prevents cash out liquidity/arbitrage issues for existing revnets which
        // are deploying to a new chain.
        _setCashOutDelayIfNeeded({revnetId: revnetId, firstStageConfig: configuration.stageConfigurations[0]});

        // Deploy the revnet's ERC-20 token.
        // slither-disable-next-line unused-return
        CONTROLLER.deployERC20For({
            projectId: revnetId,
            name: configuration.description.name,
            symbol: configuration.description.ticker,
            salt: keccak256(abi.encode(configuration.description.salt, encodedConfigurationHash, _msgSender()))
        });

        // If specified, set up the buyback hook.
        if (buybackHookConfiguration.hook != IJBBuybackHook(address(0))) {
            // Store the buyback hook.
            buybackHookOf[revnetId] = buybackHookConfiguration.hook;

            for (uint256 i; i < buybackHookConfiguration.poolConfigurations.length; i++) {
                // Set the pool being iterated on.
                REVBuybackPoolConfig calldata poolConfig = buybackHookConfiguration.poolConfigurations[i];

                // Register the pool within the buyback contract.
                // slither-disable-next-line unused-return
                buybackHookConfiguration.hook.setPoolFor({
                    projectId: revnetId,
                    fee: poolConfig.fee,
                    twapWindow: poolConfig.twapWindow,
                    twapSlippageTolerance: poolConfig.twapSlippageTolerance,
                    terminalToken: poolConfig.token
                });
            }
        }

        // If specified, set up the loan contract.
        if (configuration.loans != address(0)) {
            _setPermission({
                operator: address(configuration.loans),
                revnetId: revnetId,
                permissionId: JBPermissionIds.USE_ALLOWANCE
            });
            loansOf[revnetId] = configuration.loans;
        }

        // Give the split operator their permissions.
        _setSplitOperatorOf({revnetId: revnetId, operator: configuration.splitOperator});

        // Deploy the suckers (if applicable).
        if (suckerDeploymentConfiguration.salt != bytes32(0)) {
            _deploySuckersFor({
                revnetId: revnetId,
                encodedConfigurationHash: encodedConfigurationHash,
                suckerDeploymentConfiguration: suckerDeploymentConfiguration
            });
        }

        // Store the hashed encoded configuration.
        hashedEncodedConfigurationOf[revnetId] = encodedConfigurationHash;

        emit DeployRevnet({
            revnetId: revnetId,
            configuration: configuration,
            terminalConfigurations: terminalConfigurations,
            buybackHookConfiguration: buybackHookConfiguration,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration,
            rulesetConfigurations: rulesetConfigurations,
            encodedConfigurationHash: encodedConfigurationHash,
            caller: _msgSender()
        });
    }

    /// @notice Deploy suckers for a revnet.
    /// @param revnetId The ID of the revnet to deploy suckers for.
    /// @param encodedConfigurationHash A hash that represents the revnet's configuration.
    /// See `_makeRulesetConfigurations(…)` for encoding details. Clients can read the encoded configuration
    /// from the `DeployRevnet` event emitted by this contract.
    /// @param suckerDeploymentConfiguration The suckers to set up for the revnet.
    function _deploySuckersFor(
        uint256 revnetId,
        bytes32 encodedConfigurationHash,
        REVSuckerDeploymentConfig calldata suckerDeploymentConfiguration
    )
        internal
        returns (address[] memory suckers)
    {
        emit DeploySuckers({
            revnetId: revnetId,
            encodedConfigurationHash: encodedConfigurationHash,
            suckerDeploymentConfiguration: suckerDeploymentConfiguration,
            caller: _msgSender()
        });

        // Deploy the suckers.
        // slither-disable-next-line unused-return
        suckers = SUCKER_REGISTRY.deploySuckersFor({
            projectId: revnetId,
            salt: keccak256(abi.encode(encodedConfigurationHash, suckerDeploymentConfiguration.salt, _msgSender())),
            configurations: suckerDeploymentConfiguration.deployerConfigurations
        });
    }

    /// @notice Convert a revnet's stages into a series of Juicebox project rulesets.
    /// @param revnetId The ID of the revnet to make rulesets for.
    /// @param configuration The configuration containing the revnet's stages.
    /// @param terminalConfigurations The terminals to set up for the revnet. Used for payments and cash outs.
    /// @return rulesetConfigurations A list of ruleset configurations defined by the stages.
    /// @return encodedConfigurationHash A hash that represents the revnet's configuration. Used for sucker
    /// deployment salts.
    function _makeRulesetConfigurations(
        uint256 revnetId,
        REVConfig calldata configuration,
        JBTerminalConfig[] calldata terminalConfigurations
    )
        internal
        returns (JBRulesetConfig[] memory rulesetConfigurations, bytes32 encodedConfigurationHash)
    {
        // If there are no stages, revert.
        if (configuration.stageConfigurations.length == 0) revert REVDeployer_StagesRequired();

        // Initialize the array of rulesets.
        rulesetConfigurations = new JBRulesetConfig[](configuration.stageConfigurations.length);

        // Add the base configuration to the byte-encoded configuration.
        bytes memory encodedConfiguration = abi.encode(
            configuration.baseCurrency,
            configuration.loans,
            configuration.description.name,
            configuration.description.ticker,
            configuration.description.salt
        );

        // Initialize fund access limit groups for the loan contract to use.
        JBFundAccessLimitGroup[] memory fundAccessLimitGroups =
            _makeLoanFundAccessLimits({configuration: configuration, terminalConfigurations: terminalConfigurations});

        // Iterate through each stage to set up its ruleset.
        for (uint256 i; i < configuration.stageConfigurations.length; i++) {
            // Set the stage being iterated on.
            REVStageConfig calldata stageConfiguration = configuration.stageConfigurations[i];

            // Make sure the revnet has at least one split if it has a split percent.
            // Otherwise, the split would go to this contract since its the revnet's owner.
            if (stageConfiguration.splitPercent > 0 && stageConfiguration.splits.length == 0) {
                revert REVDeployer_MustHaveSplits();
            }

            // If the stage's start time is not after the previous stage's start time, revert.
            if (i > 0 && stageConfiguration.startsAtOrAfter <= configuration.stageConfigurations[i - 1].startsAtOrAfter)
            {
                revert REVDeployer_StageTimesMustIncrease();
            }

            // Make sure the revnet doesn't prevent cashouts all together.
            if (stageConfiguration.cashOutTaxRate >= JBConstants.MAX_CASH_OUT_TAX_RATE) {
                revert REVDeployer_CashOutsCantBeTurnedOffCompletely(
                    stageConfiguration.cashOutTaxRate, JBConstants.MAX_CASH_OUT_TAX_RATE
                );
            }

            // Set up the ruleset.
            rulesetConfigurations[i] = _makeRulesetConfiguration({
                baseCurrency: configuration.baseCurrency,
                stageConfiguration: stageConfiguration,
                fundAccessLimitGroups: fundAccessLimitGroups
            });

            // Add the stage's properties to the byte-encoded configuration.
            encodedConfiguration = abi.encode(
                encodedConfiguration,
                // If no start time is provided for the first stage, use the current block's timestamp.
                // In the future, revnets deployed on other networks can match this revnet's encoded stage by specifying
                // the
                // same start time.
                (i == 0 && stageConfiguration.startsAtOrAfter == 0)
                    ? block.timestamp
                    : stageConfiguration.startsAtOrAfter,
                stageConfiguration.splitPercent,
                stageConfiguration.initialIssuance,
                stageConfiguration.issuanceCutFrequency,
                stageConfiguration.issuanceCutPercent,
                stageConfiguration.cashOutTaxRate
            );

            // Add each auto-mint to the byte-encoded representation.
            for (uint256 j; j < stageConfiguration.autoIssuances.length; j++) {
                REVAutoIssuance calldata autoIssuance = stageConfiguration.autoIssuances[j];

                // Make sure the beneficiary is not the zero address.
                if (autoIssuance.beneficiary == address(0)) revert REVDeployer_AutoIssuanceBeneficiaryZeroAddress();

                // If there's nothing to auto-mint, continue.
                if (autoIssuance.count == 0) continue;

                encodedConfiguration =
                    abi.encode(encodedConfiguration, autoIssuance.chainId, autoIssuance.beneficiary, autoIssuance.count);

                // If the issuance config is for another chain, skip it.
                if (autoIssuance.chainId != block.chainid) continue;

                emit StoreAutoIssuanceAmount({
                    revnetId: revnetId,
                    stageId: block.timestamp + i,
                    beneficiary: autoIssuance.beneficiary,
                    count: autoIssuance.count,
                    caller: _msgSender()
                });

                // Store the amount of tokens that can be auto-minted on this chain during this stage.
                // The first stage ID is stored at this block's timestamp,
                // and further stage IDs have incrementally increasing IDs
                // slither-disable-next-line reentrancy-events
                amountToAutoIssue[revnetId][block.timestamp + i][autoIssuance.beneficiary] += autoIssuance.count;
            }
        }

        // Hash the encoded configuration.
        encodedConfigurationHash = keccak256(encodedConfiguration);
    }

    /// @notice Sets the cash out delay if the revnet's stages are already in progress.
    /// @dev This prevents cash out liquidity/arbitrage issues for existing revnets which
    /// are deploying to a new chain.
    /// @param revnetId The ID of the revnet to set the cash out delay for.
    /// @param firstStageConfig The revnet's first stage.
    function _setCashOutDelayIfNeeded(uint256 revnetId, REVStageConfig calldata firstStageConfig) internal {
        // If this is the first revnet being deployed (with a `startsAtOrAfter` of 0),
        // or if the first stage hasn't started yet, we don't need to set a cash out delay.
        if (firstStageConfig.startsAtOrAfter == 0 || firstStageConfig.startsAtOrAfter >= block.timestamp) return;

        // Calculate the timestamp at which the cash out delay ends.
        uint256 cashOutDelay = block.timestamp + CASH_OUT_DELAY;

        // Store the cash out delay.
        cashOutDelayOf[revnetId] = cashOutDelay;

        emit SetCashOutDelay({revnetId: revnetId, cashOutDelay: cashOutDelay, caller: _msgSender()});
    }

    /// @notice Grants a permission to an address (an "operator").
    /// @param operator The address to give the permission to.
    /// @param revnetId The ID of the revnet to scope the permission for.
    /// @param permissionId The ID of the permission to set. See `JBPermissionIds`.
    function _setPermission(address operator, uint256 revnetId, uint8 permissionId) internal {
        uint8[] memory permissionsIds = new uint8[](1);
        permissionsIds[0] = permissionId;

        // Give the operator the permission.
        _setPermissionsFor({
            account: address(this),
            operator: operator,
            revnetId: revnetId,
            permissionIds: permissionsIds
        });
    }

    /// @notice Grants a permission to an address (an "operator").
    /// @param account The account granting the permission.
    /// @param operator The address to give the permission to.
    /// @param revnetId The ID of the revnet to scope the permission for.
    /// @param permissionIds An array of permission IDs to set. See `JBPermissionIds`.
    function _setPermissionsFor(
        address account,
        address operator,
        uint256 revnetId,
        uint8[] memory permissionIds
    )
        internal
    {
        // Set up the permission data.
        JBPermissionsData memory permissionData =
            JBPermissionsData({operator: operator, projectId: uint64(revnetId), permissionIds: permissionIds});

        // Set the permissions.
        PERMISSIONS.setPermissionsFor({account: account, permissionsData: permissionData});
    }

    /// @notice Give a split operator their permissions.
    /// @dev Only a revnet's current split operator can set a new split operator, by calling `setSplitOperatorOf(…)`.
    /// @param revnetId The ID of the revnet to set the split operator of.
    /// @param operator The new split operator's address.
    function _setSplitOperatorOf(uint256 revnetId, address operator) internal {
        // Get the permission indexes for the split operator.
        uint256[] memory permissionIndexes = _splitOperatorPermissionIndexesOf(revnetId);
        uint8[] memory permissionIds = new uint8[](permissionIndexes.length);

        for (uint256 i; i < permissionIndexes.length; i++) {
            permissionIds[i] = uint8(permissionIndexes[i]);
        }

        _setPermissionsFor({
            account: address(this),
            operator: operator,
            revnetId: revnetId,
            permissionIds: permissionIds
        });
    }
}
