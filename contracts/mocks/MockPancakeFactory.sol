// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MockPancakePair.sol";

contract MockPancakeFactory {
    mapping(address => mapping(address => address)) public pairs;
    address[] public allPairs;
    
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "Identical addresses");
        require(tokenA != address(0) && tokenB != address(0), "Zero address");
        require(pairs[tokenA][tokenB] == address(0), "Pair exists");
        
        // Deploy mock pair
        MockPancakePair pairContract = new MockPancakePair(tokenA, tokenB);
        pair = address(pairContract);
        
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
        allPairs.push(pair);
        
        emit PairCreated(tokenA, tokenB, pair, allPairs.length);
    }
    
    function getPair(address tokenA, address tokenB) external view returns (address) {
        return pairs[tokenA][tokenB];
    }
    
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }
}