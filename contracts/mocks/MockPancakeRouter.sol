// contracts/mocks/MockPancakeRouter.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockPancakeRouter {
    address public immutable WETH;
    address public immutable factory;
    
    constructor(address _weth, address _factory) {
        WETH = _weth;
        factory = _factory;
    }
    
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint, uint, uint) {
        require(deadline >= block.timestamp, "Expired");
        
        IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
        
        return (amountTokenDesired, msg.value, 1000); // Mock LP tokens
    }
    
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external {
        require(deadline >= block.timestamp, "Expired");
        require(path.length >= 2, "Invalid path");
        
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        
        uint ethAmount = amountIn / 1000; // Mock: 1 ETH per 1000 tokens
        require(ethAmount >= amountOutMin, "Insufficient output");
        
        payable(to).transfer(ethAmount);
    }
    
    function getAmountsOut(uint amountIn, address[] calldata path)
        external view returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[1] = amountIn / 1000; // Mock: 1 ETH per 1000 tokens
    }
    
    receive() external payable {}
}