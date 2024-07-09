// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {JSONScript} from '../helpers/JSONScript.s.sol';
import {ODGovernor} from '@opendollar/contracts/gov/ODGovernor.sol';
import {IERC20} from '@openzeppelin/token/ERC20/IERC20.sol';
import {Generator} from '../Generator.s.sol';
import {Strings} from '@openzeppelin/utils/Strings.sol';
import {IBaseOracle} from '@opendollar/interfaces/oracles/IBaseOracle.sol';
import {IDenominatedOracleFactory} from '@opendollar/interfaces/factories/IDenominatedOracleFactory.sol';
import 'forge-std/StdJson.sol';

/// @title GenerateDeployDenominatedOraclesProposal Script
/// @author OpenDollar
/// @notice Script to generate a new chainlink relayer
/// @dev This script is used to create a proposal input to use the DenominatedOracleFactory to deploy a new chainlink relayer
contract GenerateDeployDenominatedOraclesProposal is Generator, JSONScript {
  using stdJson for string;

  string public description;
  address public governanceAddress;
  address public chainlinkRelayerFactory;
  address[] public chainlinkPriceFeed;
  address[] public chainlinkRelayer;
  bool[] public inverted;

  function _loadBaseData(string memory json) internal override {
    governanceAddress = json.readAddress(string(abi.encodePacked('.ODGovernor_Address:')));
    description = json.readString(string(abi.encodePacked('.description')));
    chainlinkRelayerFactory = json.readAddress(string(abi.encodePacked('.DenominatedOracleFactory_Address')));
    uint256 len = json.readUint(string(abi.encodePacked('.arrayLength')));

    for (uint256 i; i < len; i++) {
      string memory index = Strings.toString(i);
      address feed = json.readAddress(string(abi.encodePacked('.objectArray[', index, '].chainlinkPriceFeed')));
      address relayer = json.readAddress(string(abi.encodePacked('.objectArray[', index, '].chainlinkRelayer')));
      bool _inverted = json.readBool(string(abi.encodePacked('.objectArray[', index, '].inverted')));
      chainlinkPriceFeed.push(feed);
      chainlinkRelayer.push(relayer);
      inverted.push(_inverted);
    }
  }

  function _generateProposal() internal override {
    ODGovernor gov = ODGovernor(payable(governanceAddress));

    uint256 len = chainlinkRelayer.length;
    require(len == inverted.length, 'DENOMINATED ORACLE PROPOSER: mismatched array lengths');

    address[] memory targets = new address[](len);
    uint256[] memory values = new uint256[](len);
    bytes[] memory calldatas = new bytes[](len);

    for (uint256 i = 0; i < len; i++) {
      // encode relayer factory function data
      calldatas[i] = abi.encodeWithSelector(
        IDenominatedOracleFactory.deployDenominatedOracle.selector,
        IBaseOracle(chainlinkPriceFeed[i]),
        IBaseOracle(chainlinkRelayer[i]),
        inverted[i]
      );
      targets[i] = chainlinkRelayerFactory;
      values[i] = 0; // value is always 0
    }

    // Get the description and descriptionHash
    bytes32 descriptionHash = keccak256(bytes(description));
    FileNameStrings memory fileNameStrings;

    // Propose the action
    fileNameStrings.proposalIdUint = gov.hashProposal(targets, values, calldatas, descriptionHash);
    fileNameStrings.shortProposalId = vm.toString(fileNameStrings.proposalIdUint / 10 ** 69);
    fileNameStrings.proposalId = vm.toString(fileNameStrings.proposalIdUint);

    (fileNameStrings.year, fileNameStrings.month, fileNameStrings.day) = timestampToDate(block.timestamp);
    fileNameStrings.formattedDate = string.concat(
      vm.toString(fileNameStrings.month), '_', vm.toString(fileNameStrings.day), '_', vm.toString(fileNameStrings.year)
    );

    {
      // Build the JSON output
      string memory objectKey = 'PROPOSE_DEPLOY_DENOMINATED_ORACLE_KEY';
      string memory jsonOutput = _buildProposalParamsJSON(
        fileNameStrings.proposalId, objectKey, targets, values, calldatas, description, descriptionHash
      );
      vm.writeJson(
        jsonOutput,
        string.concat(
          './gov-output/',
          _network,
          '/deploy-denominated-oracle-',
          fileNameStrings.formattedDate,
          '-',
          fileNameStrings.shortProposalId,
          '.json'
        )
      );
    }
  }

  function _serializeCurrentJson(string memory _objectKey) internal override returns (string memory _serializedInput) {
    _serializedInput = vm.serializeJson(_objectKey, json);
  }
}
