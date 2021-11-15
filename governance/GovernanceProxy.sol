// SPDX-License-Identifier: None

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract OnChainGovernanceProxy is Proxy, Ownable {
    
    address implementation;
    
    function _implementation() override internal view returns(address) {
        return implementation;
    }
    
    function changeImplementation(address _newImplementation) public onlyOwner {
        implementation = _newImplementation;
    }
    fallback(bytes calldata) external override payable returns (bytes memory){
        (, bytes memory data) = implementation.delegatecall(msg.data);
        return data;
    }
}
