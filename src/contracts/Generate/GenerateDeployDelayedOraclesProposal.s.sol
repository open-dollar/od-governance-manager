// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {JSONScript} from '../helpers/JSONScript.s.sol';
import {ODGovernor} from '@opendollar/contracts/gov/ODGovernor.sol';
import {Generator} from '../Generator.s.sol';
import {Strings} from '@openzeppelin/utils/Strings.sol';
import {IBaseOracle} from '@opendollar/interfaces/oracles/IBaseOracle.sol';
import {IDelayedOracleFactory} from '@opendollar/interfaces/factories/IDelayedOracleFactory.sol';
import 'forge-std/StdJson.sol';

/// @title GenerateDeployDelayedOraclesProposal Script
/// @author OpenDollar
/// @notice Script to generate a new chainlink relayer
/// @dev This script is used to create a proposal input to use the DenominatedOracleFactory to deploy a new chainlink relayer
contract GenerateDeployDelayedOraclesProposal is Generator, JSONScript {
  using stdJson for string;

  string public description;
  address public governanceAddress;
  address public delayedOracleFactory;
  address[] public priceFeed;
  uint256[] public interval;

  function _loadBaseData(string memory json) internal override {
    governanceAddress = json.readAddress(string(abi.encodePacked('.ODGovernor_Address:')));
    description = json.readString(string(abi.encodePacked('.description')));
    delayedOracleFactory = json.readAddress(string(abi.encodePacked('.DelayedOracleFactory_Address')));
    uint256 len = json.readUint(string(abi.encodePacked('.arrayLength')));

    for (uint256 i; i < len; i++) {
      string memory index = Strings.toString(i);
      address feed = json.readAddress(string(abi.encodePacked('.objectArray[', index, '].priceFeed')));
      uint256 _interval = json.readUint(string(abi.encodePacked('.objectArray[', index, '].interval')));
      priceFeed.push(feed);
      interval.push(_interval);
    }
  }

  function _generateProposal() internal override {
    ODGovernor gov = ODGovernor(payable(governanceAddress));

    uint256 len = priceFeed.length;
    require(len == interval.length, 'DELAYED ORACLE PROPOSER: mismatched array lengths');

    address[] memory targets = new address[](len);
    uint256[] memory values = new uint256[](len);
    bytes[] memory calldatas = new bytes[](len);

    for (uint256 i = 0; i < len; i++) {
      // encode relayer factory function data
      calldatas[i] = abi.encodeWithSelector(
        IDelayedOracleFactory.deployDelayedOracle.selector, IBaseOracle(priceFeed[i]), interval[i]
      );
      targets[i] = delayedOracleFactory;
      values[i] = 0; // value is always 0
    }

    // Get the description and descriptionHash
    bytes32 descriptionHash = keccak256(bytes(description));

    // Propose the action
    uint256 proposalId = gov.hashProposal(targets, values, calldatas, descriptionHash);
    string memory stringProposalId = vm.toString(proposalId / 10 ** 69);

    {
      // Build the JSON output
      string memory objectKey = 'PROPOSE_DEPLOY_DELAYED_ORACLE_KEY';
      string memory jsonOutput =
        _buildProposalParamsJSON(proposalId, objectKey, targets, values, calldatas, description, descriptionHash);
      vm.writeJson(
        jsonOutput, string.concat('./gov-output/', _network, '/deploy-delayed-oracle-', stringProposalId, '.json')
      );
    }
  }

  function _serializeCurrentJson(string memory _objectKey) internal override returns (string memory _serializedInput) {
    _serializedInput = vm.serializeJson(_objectKey, json);
  }
}
