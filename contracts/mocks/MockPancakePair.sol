// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockPancakePair is ERC20 {
    address public token0;
    address public token1;
    
    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;
    
    constructor(address _token0, address _token1) ERC20("PancakePair", "CAKE-LP") {
        token0 = _token0;
        token1 = _token1;
    }
    
    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }
    
    function sync() external {
        reserve0 = uint112(IERC20(token0).balanceOf(address(this)));
        reserve1 = uint112(IERC20(token1).balanceOf(address(this)));
        blockTimestampLast = uint32(block.timestamp);
    }
    
    // Simplified mint for testing
    function mint(address to) external returns (uint liquidity) {
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        
        uint amount0 = balance0 - reserve0;
        uint amount1 = balance1 - reserve1;
        
        liquidity = 1000; // Simplified calculation
        _mint(to, liquidity);
        
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);
    }
}