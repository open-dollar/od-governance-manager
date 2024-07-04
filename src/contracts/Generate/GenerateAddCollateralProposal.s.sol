// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {JSONScript} from '../helpers/JSONScript.s.sol';
import {ODGovernor} from '@opendollar/contracts/gov/ODGovernor.sol';
import {Generator} from '../Generator.s.sol';
import {IGlobalSettlement} from '@opendollar/contracts/settlement/GlobalSettlement.sol';
import {ICollateralJoinFactory} from '@opendollar/interfaces/factories/ICollateralJoinFactory.sol';
import {IAuthorizable} from '@opendollar/interfaces/utils/IAuthorizable.sol';
import {IModifiablePerCollateral} from '@opendollar/interfaces/utils/IModifiablePerCollateral.sol';
import {ICollateralAuctionHouse} from '@opendollar/interfaces/ICollateralAuctionHouse.sol';
import {ISAFEEngine} from '@opendollar/interfaces/ISAFEEngine.sol';
import {ITaxCollector} from '@opendollar/interfaces/ITaxCollector.sol';
import {ILiquidationEngine} from '@opendollar/interfaces/ILiquidationEngine.sol';
import {IOracleRelayer} from '@opendollar/contracts/OracleRelayer.sol';
import {IDelayedOracle} from '@opendollar/interfaces/oracles/IDelayedOracle.sol';
import {CollateralAuctionHouseChild} from '@opendollar/contracts/factories/CollateralAuctionHouseChild.sol';
import 'forge-std/StdJson.sol';
import 'forge-std/console2.sol';

/// @title ProposeAddCollateral Script
/// @author OpenDollar
/// @notice Script to propose adding a new collateral type to the system via ODGovernance
/// @dev This script is used to propose adding a new collateral type to the system
/// @dev The script will propose a deployment of new CollateralJoin and CollateralAuctionHouse contracts
/// @dev The script will output a JSON file with the proposal data to be used by the QueueProposal and ExecuteProposal scripts
/// @dev In the root, run: export FOUNDRY_PROFILE=governance && forge script --rpc-url <RPC_URL> script/gov/AddCollateralAction/ProposeAddCollateral.s.sol
contract GenerateAddCollateralProposal is Generator, JSONScript {
  using stdJson for string;

  address public governanceAddress;
  address public globalSettlementAddress;
  address public safeEngine;
  address public taxCollector;
  address public liquidationEngine;
  address public oracleRelayer;
  address public newCAddress;

  ICollateralAuctionHouse.CollateralAuctionHouseParams internal _cahCParams;
  ISAFEEngine.SAFEEngineCollateralParams internal _SAFEEngineCollateralParams;
  ITaxCollector.TaxCollectorCollateralParams internal _taxCollectorCParams;
  ILiquidationEngine.LiquidationEngineCollateralParams internal _liquidationEngineCParams;
  IOracleRelayer.OracleRelayerCollateralParams internal _oracleCParams;

  //  struct SAFEEngineCollateralParams{
  //     // Maximum amount of debt that can be generated with the collateral type
  //     uint256 /* RAD */ collateralDebtCeiling;
  //     // Minimum amount of debt that must be generated by a SAFE using the collateral
  //     uint256 /* RAD */ collateralDebtFloor;
  //   }

  //     struct TaxCollectorCollateralParams {
  //      Per collateral stability fee
  //        uint256 /* RAY */ stabilityFee;
  // }

  //   struct LiquidationEngineCollateralParams {
  //     // Address of the collateral auction house handling liquidations for this collateral type
  //     address /*       */ collateralAuctionHouse;
  //     // Penalty applied to every liquidation involving this collateral type
  //     uint256 /* WAD % */ liquidationPenalty;
  //     // Max amount of system coins to request in one auction for this collateral type
  //     uint256 /* RAD   */ liquidationQuantity;
  //   }

  //   struct OracleRelayerCollateralParams {
  //     // Usually a DelayedOracle that enforces delays to fresh price feeds
  //     IDelayedOracle /* */ oracle;
  //     // CRatio used to compute the 'safePrice' - the price used when generating debt in SAFEEngine
  //     uint256 /* RAY    */ safetyCRatio;
  //     // CRatio used to compute the 'liquidationPrice' - the price used when liquidating SAFEs
  //     uint256 /* RAY    */ liquidationCRatio;
  //   }

  bytes32 public newCType;
  string public description;
  string public proposalType;

  function _loadBaseData(string memory json) internal override {
    proposalType = json.readString(string(abi.encodePacked('.proposalType')));
    governanceAddress = json.readAddress(string(abi.encodePacked('.ODGovernor_Address:')));
    globalSettlementAddress = json.readAddress(string(abi.encodePacked('.GlobalSettlement_Address:')));
    newCType = bytes32(abi.encodePacked(json.readString(string(abi.encodePacked('.newCollateralType')))));
    newCAddress = json.readAddress(string(abi.encodePacked('.newCollateralAddress')));
    description = json.readString(string(abi.encodePacked('.description')));
    safeEngine = json.readAddress(string(abi.encodePacked('.SAFEEngine_Address:')));
    taxCollector = json.readAddress(string(abi.encodePacked('.TaxCollector_Address:')));
    liquidationEngine = json.readAddress(string(abi.encodePacked('.LiquidationEngine_Address:')));
    oracleRelayer = json.readAddress(string(abi.encodePacked('.OracleRelayer_Address:')));

    _cahCParams.minimumBid = json.readUint(string(abi.encodePacked('.CollateralAuctionHouseParams.minimumBid')));
    _cahCParams.minDiscount = json.readUint(string(abi.encodePacked('.CollateralAuctionHouseParams.minDiscount')));
    _cahCParams.maxDiscount = json.readUint(string(abi.encodePacked('.CollateralAuctionHouseParams.maxDiscount')));
    _cahCParams.perSecondDiscountUpdateRate =
      json.readUint(string(abi.encodePacked('.CollateralAuctionHouseParams.perSecondDiscountUpdateRate')));

    _SAFEEngineCollateralParams.debtCeiling =
      json.readUint(string(abi.encodePacked('.SAFEEngineCollateralParams.collateralDebtCeiling')));
    _SAFEEngineCollateralParams.debtFloor =
      json.readUint(string(abi.encodePacked('.SAFEEngineCollateralParams.collateralDebtFloor')));

    _taxCollectorCParams.stabilityFee =
      json.readUint(string(abi.encodePacked('.TaxCollectorCollateralParams.stabilityFee')));

    _liquidationEngineCParams.collateralAuctionHouse =
      json.readAddress(string(abi.encodePacked('.LiquidationEngineCollateralParams.newCAHChild')));
    _liquidationEngineCParams.liquidationPenalty =
      json.readUint(string(abi.encodePacked('.LiquidationEngineCollateralParams.liquidationPenalty')));
    _liquidationEngineCParams.liquidationQuantity =
      json.readUint(string(abi.encodePacked('.LiquidationEngineCollateralParams.liquidationQuantity')));

    _oracleCParams.oracle =
      IDelayedOracle(json.readAddress(string(abi.encodePacked('.OracleRelayerCollateralParams.delayedOracle'))));
    _oracleCParams.safetyCRatio = json.readUint(string(abi.encodePacked('.OracleRelayerCollateralParams.safetyCRatio')));
    _oracleCParams.liquidationCRatio =
      json.readUint(string(abi.encodePacked('.OracleRelayerCollateralParams.liquidationCRatio')));
  }

  function _generateProposal() internal override {
    ODGovernor gov = ODGovernor(payable(governanceAddress));
    IGlobalSettlement globalSettlement = IGlobalSettlement(globalSettlementAddress);

    address[] memory targets = new address[](8);
    {
      targets[0] = address(globalSettlement.collateralJoinFactory());
      targets[1] = address(globalSettlement.collateralAuctionHouseFactory());
      targets[2] = safeEngine;
      targets[3] = taxCollector;
      targets[4] = liquidationEngine;
      targets[5] = oracleRelayer;
      targets[6] = safeEngine;
      targets[7] = safeEngine;
    }
    // No values needed
    uint256[] memory values = new uint256[](8);
    {
      values[0] = 0;
      values[1] = 0;
      values[2] = 0;
      values[3] = 0;
      values[4] = 0;
      values[5] = 0;
      values[6] = 0;
      values[7] = 0;
    }
    // Get calldata for:

    bytes[] memory calldatas = new bytes[](8);

    calldatas[0] = abi.encodeWithSelector(ICollateralJoinFactory.deployCollateralJoin.selector, newCType, newCAddress);

    calldatas[1] = abi.encodeWithSelector(
      IModifiablePerCollateral.initializeCollateralType.selector, newCType, abi.encode(_cahCParams)
    );
    calldatas[2] = abi.encodeWithSelector(
      IModifiablePerCollateral.initializeCollateralType.selector, newCType, abi.encode(_SAFEEngineCollateralParams)
    );
    calldatas[3] = abi.encodeWithSelector(
      IModifiablePerCollateral.initializeCollateralType.selector, newCType, abi.encode(_taxCollectorCParams)
    );
    calldatas[4] = abi.encodeWithSelector(
      IModifiablePerCollateral.initializeCollateralType.selector, newCType, abi.encode(_liquidationEngineCParams)
    );
    calldatas[5] = abi.encodeWithSelector(
      IModifiablePerCollateral.initializeCollateralType.selector, newCType, abi.encode(_oracleCParams)
    );
    calldatas[6] = abi.encodeWithSelector(
      IAuthorizable.addAuthorization.selector, abi.encode(_liquidationEngineCParams.collateralAuctionHouse)
    );
    calldatas[7] = abi.encodeWithSelector(
      ISAFEEngine.approveSAFEModification.selector, abi.encode(_liquidationEngineCParams.collateralAuctionHouse)
    );

    // Get the descriptionHash
    bytes32 descriptionHash = keccak256(bytes(description));

    // Propose the action to add the collateral type
    uint256 proposalId = gov.hashProposal(targets, values, calldatas, descriptionHash);
    string memory stringProposalId = vm.toString(proposalId / 10 ** 69);

    {
      string memory objectKey = 'PROPOSE_ADD_COLLATERAL_KEY';
      // Build the JSON output
      string memory builtProp =
        _buildProposalParamsJSON(proposalId, objectKey, targets, values, calldatas, description, descriptionHash);
      vm.writeJson(builtProp, string.concat('./gov-output/', _network, '/add-collateral-', stringProposalId, '.json'));
    }
  }

  function _serializeCurrentJson(string memory _objectKey) internal override returns (string memory _serializedInput) {
    _serializedInput = vm.serializeJson(_objectKey, json);
  }
}
