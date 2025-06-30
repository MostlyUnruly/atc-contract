// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IPancakeRouter {
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint, uint, uint);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function WETH() external pure returns (address);
    function factory() external pure returns (address);
    
    function getAmountsOut(uint amountIn, address[] calldata path) 
        external view returns (uint[] memory amounts);
}

interface IPancakeFactory {
    function createPair(address tokenA, address tokenB) external returns (address);
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IPancakePair {
    function getReserves() external view returns (uint112, uint112, uint32);
    function token0() external view returns (address);
    function sync() external;
}

contract ATC is ERC20, Ownable, ReentrancyGuard, Pausable {
    // ======== Constants ========
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant MAX_LIQUIDITY = 28_000_000 * 10**18;
    uint256 public constant MIN_ATC_FOR_PROCESSING = 1e18;
    uint256 public constant MIN_EMISSION = 1 * 10**18;
    
    uint256 public constant PHASE1_END = 730;
    uint256 public constant PHASE2_END = 2920;
    uint256 public constant PHASE1_RATE = 100 * 10**18;
    uint256 public constant PHASE2_PEAK = 3500 * 10**18;
    uint256 public constant PHASE3_DECAY = 999_950;
    
    uint256 private constant PHASE3_DECAY_SCALED = 999_950 * 10**18 / 1_000_000;
    uint256 public constant MIN_TX_AMOUNT = 100 * 10**18; // 100 ATC minimum
    uint256 public constant MAX_TX_AMOUNT_LIMIT = MAX_SUPPLY / 100; // 10M ATC maximum (1%)
    uint256 public maxTxAmount = 1_000 * 10**18; // 1,000 ATC default (adjustable)
    uint256 private constant TAX_DENOMINATOR = 10_000;
    uint256 private constant MAX_TAX_RATE = 2_500; // 25%
    uint256 private constant SLIPPAGE_TOLERANCE = 9500; // 95% (5% slippage)
    
    // ======== Timelock ========
    uint256 public constant TIMELOCK_DELAY = 1 days;
    mapping(bytes32 => uint256) private _timelocks;
    
    // ======== State Variables ========
    address public immutable router;
    address public immutable pair;
    address public immutable weth;
    
    struct TaxRates {
        uint16 buyTax;
        uint16 sellTax;
        uint16 liquidityTax;
        uint16 devTax;
        uint16 artistTax;
        uint16 marketingTax;
    }
    TaxRates public taxRates;
    
    address public devWallet;
    address public marketingWallet;
    
    uint256 public totalLiquidityAdded;
    uint256 public lastEmissionDay;
    uint256 public dailyEmission;
    uint256 public emittedToday;
    uint256 public atcForLiquidity;
    uint256 public lpTokensInContract;
    
    bool public tradingEnabled;
    uint256 private _consecutiveSwapFailures;
    
    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public automatedMarketMakerPairs;
    mapping(address => bool) private _isBlacklisted;
    mapping(address => bool) public isAntiWhaleExempt;
    
    // Memoization for daily emission
    uint256 private _lastEmissionUpdateDay;
    uint256 private _memoizedDailyEmission;
    
    // ======== Events ========
    event LiquidityAdded(uint256 atcAdded, uint256 bnbAdded, uint256 lpTokens);
    event TradingStateChanged(bool enabled);
    event TaxUpdated(uint16 buyTax, uint16 sellTax);
    event TaxDistributed(
        address indexed from,
        uint256 liquidityAmount,
        uint256 devAmount,
        uint256 artistAmount,
        uint256 marketingAmount
    );
    event TokensBurned(address indexed burner, uint256 amount);
    event EmissionUpdated(uint256 newDailyEmission, uint256 currentDay);
    event BlacklistUpdated(address indexed account, bool isBlacklisted);
    event TimelockStarted(bytes32 indexed operation, uint256 executeTime);
    event TimelockExecuted(bytes32 indexed operation);
    event TimelockCancelled(bytes32 indexed operation);
    event EmergencyWithdraw(address token, uint256 amount);
    event WalletsUpdated(address dev, address artist, address marketing);
    event SwapFailed(string reason, uint256 amount);
    event LiquidityFailed(string reason, uint256 tokenAmount, uint256 bnbAmount);
    event Deposit(address indexed from, uint256 amount);
    event LPTokensClaimed(address indexed to, uint256 amount);
    event AntiWhaleExemptUpdated(address indexed account, bool exempt);
    event AutomatedMarketMakerPairUpdated(address indexed pair, bool value);
    event ExcludedFromFeeUpdated(address indexed account, bool excluded);
    event MaxTxAmountUpdated(uint256 oldLimit, uint256 newLimit);
    
    // ======== Modifiers ========
    modifier antiWhale(address from, address to, uint256 amount) {
        if (!isExcludedFromFee[from] && !isExcludedFromFee[to] && 
            !isAntiWhaleExempt[from] && !isAntiWhaleExempt[to]) {
            require(amount <= maxTxAmount, "Transfer exceeds max transaction");
        }
        _;
    }
    
    modifier notBlacklisted(address from, address to) {
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "Address blacklisted");
        _;
    }
    
    modifier validAddress(address addr) {
        require(addr != address(0), "Zero address");
        require(addr != address(this), "Contract address");
        _;
    }
    
    modifier timelocked(string memory operation) {
        bytes32 opHash = keccak256(abi.encodePacked(operation, msg.sender));
        uint256 executeTime = _timelocks[opHash];
        
        if (executeTime == 0) {
            executeTime = block.timestamp + TIMELOCK_DELAY;
            _timelocks[opHash] = executeTime;
            emit TimelockStarted(opHash, executeTime);
            revert("Timelock initiated");
        }
        
        require(block.timestamp >= executeTime, "Timelock not expired");
        delete _timelocks[opHash];
        emit TimelockExecuted(opHash);
        _;
    }
    
    constructor(address _routerAddress) ERC20("Automator Coin", "ATC") Ownable(msg.sender) {
        require(_routerAddress != address(0), "Invalid router");
        
        // Initialize router and create pair
        router = _routerAddress;
        IPancakeRouter pancakeRouter = IPancakeRouter(_routerAddress);
        
        weth = pancakeRouter.WETH();
        require(weth != address(0), "Invalid WETH");
        
        address factory = pancakeRouter.factory();
        require(factory != address(0), "Invalid factory");
        
        // Check if pair already exists before attempting to create
        address existingPair = IPancakeFactory(factory).getPair(address(this), weth);
        pair = existingPair != address(0) 
            ? existingPair 
            : IPancakeFactory(factory).createPair(address(this), weth);
        require(pair != address(0), "Pair creation failed");
        
        automatedMarketMakerPairs[pair] = true;
        
        // Initialize wallets
        devWallet = 0x73aDd9B0Fae851F9f203Ba5346D240C32d5af259;
        marketingWallet = 0xc5e979514ebE80172EdBa7c7cfE38B599E4e4823;
        
        // Initialize tax rates (25% buy/sell tax) - UPDATED FOR SOUND MONEY
        taxRates = TaxRates({
            buyTax: 2_500,        // 25%
            sellTax: 2_500,       // 25%
            liquidityTax: 1_000,  // 10% (increased from 5%)
            devTax: 1_000,        // 10%
            artistTax: 0,         // 0% (removed)
            marketingTax: 500     // 5%
        });
        
        // Set exclusions
        isExcludedFromFee[_msgSender()] = true;
        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[devWallet] = true;
        isExcludedFromFee[marketingWallet] = true;
        
        // Set anti-whale exemptions
        isAntiWhaleExempt[_msgSender()] = true;
        isAntiWhaleExempt[address(this)] = true;
        isAntiWhaleExempt[router] = true;
        isAntiWhaleExempt[pair] = true;
        
        // Initialize emission
        lastEmissionDay = block.timestamp / 1 days;
        dailyEmission = PHASE1_RATE;
        _lastEmissionUpdateDay = lastEmissionDay;
        _memoizedDailyEmission = PHASE1_RATE;
        totalLiquidityAdded = 1_000 * 10**18;  // Ultra-scarce launch with 1,000 ATC
        
        // Pre-approve router for gas savings
        _approve(address(this), router, type(uint256).max);
        
        // Mint total supply to owner
        _mint(_msgSender(), MAX_SUPPLY);
    }
    
    // ======== Timelock Management ========
    function cancelTimelock(string memory operation) external onlyOwner {
        bytes32 opHash = keccak256(abi.encodePacked(operation, msg.sender));
        uint256 expiry = _timelocks[opHash];
        require(expiry != 0, "No active timelock");
        delete _timelocks[opHash];
        emit TimelockCancelled(opHash);
    }
    
    function getTimelockExpiry(string memory operation, address caller) external view returns (uint256) {
        return _timelocks[keccak256(abi.encodePacked(operation, caller))];
    }
    
    // ======== Owner Functions ========
    function pause() external onlyOwner timelocked("pause") {
        _pause();
    }
    
    function unpause() external onlyOwner timelocked("unpause") {
        _unpause();
    }
    
    function setTradingEnabled(bool _enabled) 
        external 
        onlyOwner 
    {
        tradingEnabled = _enabled;
        emit TradingStateChanged(_enabled);
    }
    
    function setBlacklist(address account, bool blacklisted) 
        external 
        onlyOwner 
        validAddress(account)
    {
        require(account != owner(), "Cannot blacklist owner");
        require(account != router, "Cannot blacklist router");
        require(account != pair, "Cannot blacklist pair");
        require(account != weth, "Cannot blacklist WETH");
        
        _isBlacklisted[account] = blacklisted;
        emit BlacklistUpdated(account, blacklisted);
    }
    
    function setExcludedFromFee(address account, bool excluded) 
        external 
        onlyOwner 
        validAddress(account)
    {
        isExcludedFromFee[account] = excluded;
        emit ExcludedFromFeeUpdated(account, excluded);
    }
    
    function setAntiWhaleExempt(address account, bool exempt) 
        external 
        onlyOwner 
        validAddress(account)
    {
        isAntiWhaleExempt[account] = exempt;
        emit AntiWhaleExemptUpdated(account, exempt);
    }
    
    function setMaxTxAmount(uint256 newMaxTxAmount) 
        external 
        onlyOwner 
        timelocked("setMaxTxAmount")
    {
        require(newMaxTxAmount >= MIN_TX_AMOUNT, "Below minimum limit");
        require(newMaxTxAmount <= MAX_TX_AMOUNT_LIMIT, "Exceeds maximum limit");
        require(newMaxTxAmount != maxTxAmount, "Same as current limit");
        
        uint256 oldMaxTxAmount = maxTxAmount;
        maxTxAmount = newMaxTxAmount;
        
        emit MaxTxAmountUpdated(oldMaxTxAmount, newMaxTxAmount);
    }
    
    function setAutomatedMarketMakerPair(address _pair, bool value) 
        external 
        onlyOwner 
        timelocked("setAMMPair")
        validAddress(_pair)
    {
        require(_pair != pair, "Cannot modify primary pair");
        automatedMarketMakerPairs[_pair] = value;
        emit AutomatedMarketMakerPairUpdated(_pair, value);
    }
    
    function setTaxRates(
        uint16 _buyTax,
        uint16 _sellTax,
        uint16 _liquidityTax,
        uint16 _devTax,
        uint16 _artistTax,
        uint16 _marketingTax
    ) 
        external 
        onlyOwner 
        timelocked("setTaxRates")
    {
        require(_buyTax <= MAX_TAX_RATE && _sellTax <= MAX_TAX_RATE, "Tax too high");
        
        // Ensure tax components sum to buy/sell tax rates
        uint256 totalComponents = uint256(_liquidityTax) + _devTax + _artistTax + _marketingTax;
        require(totalComponents == _buyTax && totalComponents == _sellTax, "Tax components must equal tax rate");
        
        taxRates = TaxRates({
            buyTax: _buyTax,
            sellTax: _sellTax,
            liquidityTax: _liquidityTax,
            devTax: _devTax,
            artistTax: _artistTax,
            marketingTax: _marketingTax
        });
        
        emit TaxUpdated(_buyTax, _sellTax);
    }
    
    function updateWallets(
        address _devWallet,
        address _marketingWallet
    ) 
        external 
        onlyOwner 
        timelocked("updateWallets")
        validAddress(_devWallet)
        validAddress(_marketingWallet)
    {
        // Remove old exclusions
        isExcludedFromFee[devWallet] = false;
        isExcludedFromFee[marketingWallet] = false;
        
        // Update wallets
        devWallet = _devWallet;
        marketingWallet = _marketingWallet;
        
        // Add new exclusions
        isExcludedFromFee[_devWallet] = true;
        isExcludedFromFee[_marketingWallet] = true;
        
        emit WalletsUpdated(_devWallet, address(0), _marketingWallet);
    }
    
    // ======== LP Token Management ========
    function claimLPTokens() external onlyOwner nonReentrant {
        uint256 amount = lpTokensInContract;
        require(amount > 0, "No LP tokens to claim");
        
        // Transfer first, then update state
        require(IERC20(pair).transfer(msg.sender, amount), "LP transfer failed");
        
        // Update state after successful transfer
        lpTokensInContract = 0;
        
        emit LPTokensClaimed(msg.sender, amount);
    }
    
    // ======== Testnet Helper Functions ========
    modifier onlyTestnet() {
        require(
            block.chainid == 31337 || // Hardhat
            block.chainid == 97 ||    // BSC Testnet
            block.chainid == 1337 ||  // Ganache
            block.chainid == 5777,    // Ganache CLI
            "Function only available on testnet"
        );
        _;
    }
    
    function setLastEmissionDay(uint256 day) external onlyOwner onlyTestnet {
        require(day <= block.timestamp / 1 days, "Cannot set future day");
        lastEmissionDay = day;
        _updateEmission();
        // Sync memoization
        _lastEmissionUpdateDay = block.timestamp / 1 days;
        _memoizedDailyEmission = dailyEmission;
        emit EmissionUpdated(dailyEmission, day);
    }
    
    function setTotalLiquidityAdded(uint256 amount) external onlyOwner onlyTestnet {
        require(amount <= MAX_LIQUIDITY, "Exceeds max liquidity");
        totalLiquidityAdded = amount;
    }
    
    function setDailyEmission(uint256 emission) external onlyOwner onlyTestnet {
        require(emission >= MIN_EMISSION, "Below minimum emission");
        require(emission <= PHASE2_PEAK, "Above maximum emission");
        dailyEmission = emission;
        _memoizedDailyEmission = emission;
        _lastEmissionUpdateDay = block.timestamp / 1 days;
        emit EmissionUpdated(emission, block.timestamp / 1 days);
    }
    
    function setEmittedToday(uint256 amount) external onlyOwner onlyTestnet {
        require(amount <= dailyEmission, "Exceeds daily emission");
        emittedToday = amount;
    }
    
    function setAtcForLiquidity(uint256 amount) external onlyOwner onlyTestnet {
        require(amount <= balanceOf(address(this)), "Exceeds contract balance");
        atcForLiquidity = amount;
    }
    
    function simulateTimeTravel(uint256 daysToAdvance) external onlyOwner onlyTestnet {
        require(daysToAdvance > 0 && daysToAdvance <= 365, "Invalid days");
        uint256 newDay = lastEmissionDay + daysToAdvance;
        lastEmissionDay = newDay;
        _updateEmission();
        // Ensure memoization is synced
        _lastEmissionUpdateDay = block.timestamp / 1 days;
        _memoizedDailyEmission = dailyEmission;
    }
    
    // ======== Emergency Functions ========
    function withdrawStuckBNB() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No BNB");
        
        (bool success,) = payable(devWallet).call{value: balance}("");
        require(success, "Transfer failed");
        
        emit EmergencyWithdraw(address(0), balance);
    }
    
    function withdrawStuckTokens(address token) external onlyOwner nonReentrant validAddress(token) {
        require(token != address(this), "Cannot withdraw ATC");
        require(token != pair, "Cannot withdraw LP tokens directly");
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens");
        
        require(IERC20(token).transfer(devWallet, balance), "Transfer failed");
        
        emit EmergencyWithdraw(token, balance);
    }
    
    function emergencyLiquidityRelease() external onlyOwner nonReentrant whenNotPaused {
        require(totalLiquidityAdded >= MAX_LIQUIDITY, "Not at max liquidity");
        require(atcForLiquidity > 0, "No liquidity tokens");
        
        uint256 amount = atcForLiquidity;
        atcForLiquidity = 0;
        
        super._update(address(this), devWallet, amount);
        
        // Only sync if ATC is token0 to avoid incorrect reserve updates
        if (IPancakePair(pair).token0() == address(this)) {
            IPancakePair(pair).sync();
        }
    }
    
    // ======== Transfer Functions ========
    function _update(
        address from,
        address to,
        uint256 amount
    ) 
        internal 
        override 
        whenNotPaused
        notBlacklisted(from, to)
        antiWhale(from, to, amount)
    {
        if (from != address(0) && to != address(0)) {
            // This is a transfer
            require(amount > 0, "Zero amount");
            
            // Update emission before transfer
            _updateEmission();
            
            // Check trading status
            if (!tradingEnabled) {
                require(
                    isExcludedFromFee[from] || isExcludedFromFee[to],
                    "Trading not enabled"
                );
            }
            
            // Check if we should take fee
            bool takeFee = !isExcludedFromFee[from] && !isExcludedFromFee[to];
            
            // Process transfer with or without fee
            if (takeFee && (automatedMarketMakerPairs[to] || automatedMarketMakerPairs[from])) {
                _transferWithTax(from, to, amount);
                return; // Don't call super._update as we handle the transfer in _transferWithTax
            }
        }
        
        // For regular transfers, mints, and burns
        super._update(from, to, amount);
        
        // Process liquidity if selling to AMM and not in swap
        if (from != address(0) && automatedMarketMakerPairs[to] && from != address(this)) {
            _processLiquidity();
        }
    }
    
    function _transferWithTax(
        address from,
        address to,
        uint256 amount
    ) private {
        bool isSell = automatedMarketMakerPairs[to];
        uint256 taxRate = isSell ? taxRates.sellTax : taxRates.buyTax;
        
        uint256 taxAmount = (amount * taxRate) / TAX_DENOMINATOR;
        uint256 transferAmount = amount - taxAmount;
        
        // Calculate tax distribution based on actual tax rate
        uint256 totalTaxBasis = taxRate; // Use actual tax rate as basis
        uint256 liquidityAmount = (taxAmount * taxRates.liquidityTax) / totalTaxBasis;
        uint256 devAmount = (taxAmount * taxRates.devTax) / totalTaxBasis;
        uint256 marketingAmount = (taxAmount * taxRates.marketingTax) / totalTaxBasis;
        
        // Handle any dust from rounding
        uint256 dust = taxAmount - (liquidityAmount + devAmount + marketingAmount);
        if (dust > 0) {
            marketingAmount += dust;
        }
        
        // Transfer main amount
        super._update(from, to, transferAmount);
        
        // Distribute taxes
        if (liquidityAmount > 0) {
            super._update(from, address(this), liquidityAmount);
            unchecked {
                atcForLiquidity = atcForLiquidity + liquidityAmount;
            }
        }
        
        if (devAmount > 0) {
            super._update(from, devWallet, devAmount);
        }
        
        if (marketingAmount > 0) {
            super._update(from, marketingWallet, marketingAmount);
        }
        
        emit TaxDistributed(from, liquidityAmount, devAmount, 0, marketingAmount);
    }
    
    // ======== Liquidity Processing ========
    function _processLiquidity() private nonReentrant {
        if (atcForLiquidity < MIN_ATC_FOR_PROCESSING) return;
        
        uint256 availableEmission = dailyEmission > emittedToday ? 
            dailyEmission - emittedToday : 0;
            
        uint256 remainingLiquidity = totalLiquidityAdded >= MAX_LIQUIDITY ? 
            0 : MAX_LIQUIDITY - totalLiquidityAdded;
            
        uint256 atcToAdd = _min(
            atcForLiquidity,
            availableEmission,
            remainingLiquidity
        );
        
        if (atcToAdd < MIN_ATC_FOR_PROCESSING) return;
        
        uint256 halfAtc = atcToAdd / 2;
        uint256 otherHalf = atcToAdd - halfAtc;
        
        uint256 initialBalance = address(this).balance;
        
        // Swap half for BNB with slippage protection
        if (_swapTokensForBNB(halfAtc)) {
            uint256 bnbReceived = address(this).balance - initialBalance;
            
            if (bnbReceived > 0) {
                (bool success, uint256 lpTokensReceived) = _addLiquidity(otherHalf, bnbReceived);
                if (success) {
                    unchecked {
                        atcForLiquidity = atcForLiquidity - atcToAdd;
                        totalLiquidityAdded = totalLiquidityAdded + otherHalf;
                        emittedToday = emittedToday + atcToAdd;
                        lpTokensInContract = lpTokensInContract + lpTokensReceived;
                    }
                    _consecutiveSwapFailures = 0; // Reset failure counter
                }
            }
        } else {
            unchecked {
                _consecutiveSwapFailures++;
            }
            if (_consecutiveSwapFailures > 5) {
                emit SwapFailed("Multiple consecutive failures", halfAtc);
            }
        }
    }
    
    function _swapTokensForBNB(uint256 tokenAmount) private returns (bool) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = weth;
        
        // Try to get expected output with NO fallback to zero
        uint256 amountOutMin;
        try IPancakeRouter(router).getAmountsOut(tokenAmount, path) returns (uint256[] memory amounts) {
            amountOutMin = (amounts[1] * SLIPPAGE_TOLERANCE) / TAX_DENOMINATOR;
        } catch {
            // If oracle fails, abort the swap entirely
            emit SwapFailed("Oracle failure", tokenAmount);
            return false;
        }
        
        try IPancakeRouter(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 300
        ) {
            return true;
        } catch Error(string memory reason) {
            emit SwapFailed(reason, tokenAmount);
            return false;
        } catch {
            emit SwapFailed("Unknown error", tokenAmount);
            return false;
        }
    }
    
    function _addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private returns (bool, uint256) {
        // Apply slippage tolerance to both token and BNB amounts
        uint256 tokenMin = (tokenAmount * SLIPPAGE_TOLERANCE) / TAX_DENOMINATOR;
        uint256 bnbMin = (bnbAmount * SLIPPAGE_TOLERANCE) / TAX_DENOMINATOR;
        
        try IPancakeRouter(router).addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            tokenMin,
            bnbMin,
            address(this), // LP tokens to contract, not devWallet
            block.timestamp + 300
        ) returns (uint256, uint256, uint256 liquidity) {
            emit LiquidityAdded(tokenAmount, bnbAmount, liquidity);
            return (true, liquidity);
        } catch Error(string memory reason) {
            emit LiquidityFailed(reason, tokenAmount, bnbAmount);
            return (false, 0);
        } catch {
            emit LiquidityFailed("Unknown error", tokenAmount, bnbAmount);
            return (false, 0);
        }
    }
    
    function manualProcessLiquidity() external onlyOwner nonReentrant whenNotPaused {
        _processLiquidity();
        // Reset failure counter on manual call
        _consecutiveSwapFailures = 0;
    }
    
    // ======== Liquidity Tax Management Functions ========
    function withdrawLiquidityTax(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Zero amount");
        require(amount <= atcForLiquidity, "Insufficient balance");
        
        atcForLiquidity -= amount;
        super._update(address(this), owner(), amount);
    }

    function withdrawAllLiquidityTax() external onlyOwner nonReentrant {
        uint256 amount = atcForLiquidity;
        require(amount > 0, "No liquidity tax");
        
        atcForLiquidity = 0;
        super._update(address(this), owner(), amount);
    }

    function addAllLiquidityTax() external onlyOwner nonReentrant whenNotPaused {
        require(atcForLiquidity >= MIN_ATC_FOR_PROCESSING, "Insufficient ATC");
        
        uint256 atcAmount = atcForLiquidity;
        uint256 halfAtc = atcAmount / 2;
        uint256 otherHalf = atcAmount - halfAtc;
        
        uint256 initialBalance = address(this).balance;
        
        // Swap half for BNB
        require(_swapTokensForBNB(halfAtc), "Swap failed");
        
        uint256 bnbReceived = address(this).balance - initialBalance;
        require(bnbReceived > 0, "No BNB received");
        
        // Add liquidity
        (bool success, uint256 lpTokensReceived) = _addLiquidity(otherHalf, bnbReceived);
        require(success, "Liquidity addition failed");
        
        // Update state on success
        atcForLiquidity = 0;
        unchecked {
            totalLiquidityAdded = totalLiquidityAdded + otherHalf;
            lpTokensInContract = lpTokensInContract + lpTokensReceived;
        }
    }

    function addSpecificLiquidityTax(uint256 atcAmount) external onlyOwner nonReentrant whenNotPaused {
        require(atcAmount > 0 && atcAmount <= atcForLiquidity, "Invalid amount");
        require(atcAmount >= MIN_ATC_FOR_PROCESSING, "Below minimum");
        
        uint256 halfAtc = atcAmount / 2;
        uint256 otherHalf = atcAmount - halfAtc;
        
        uint256 initialBalance = address(this).balance;
        
        // Swap half for BNB
        require(_swapTokensForBNB(halfAtc), "Swap failed");
        
        uint256 bnbReceived = address(this).balance - initialBalance;
        require(bnbReceived > 0, "No BNB received");
        
        // Add liquidity
        (bool success, uint256 lpTokensReceived) = _addLiquidity(otherHalf, bnbReceived);
        require(success, "Liquidity addition failed");
        
        // Update state on success
        atcForLiquidity -= atcAmount;
        unchecked {
            totalLiquidityAdded = totalLiquidityAdded + otherHalf;
            lpTokensInContract = lpTokensInContract + lpTokensReceived;
        }
    }

    // ======== Flexible Liquidity Management ========
    function addContractATCToLiquidity(uint256 atcAmount) external onlyOwner nonReentrant whenNotPaused {
        uint256 availableATC = balanceOf(address(this)) - atcForLiquidity; // Exclude tax-allocated ATC
        require(atcAmount > 0 && atcAmount <= availableATC, "Invalid amount");
        require(atcAmount >= MIN_ATC_FOR_PROCESSING, "Below minimum");
        
        uint256 halfAtc = atcAmount / 2;
        uint256 otherHalf = atcAmount - halfAtc;
        
        uint256 initialBalance = address(this).balance;
        
        // Swap half for BNB
        require(_swapTokensForBNB(halfAtc), "Swap failed");
        
        uint256 bnbReceived = address(this).balance - initialBalance;
        require(bnbReceived > 0, "No BNB received");
        
        // Add liquidity
        (bool success, uint256 lpTokensReceived) = _addLiquidity(otherHalf, bnbReceived);
        require(success, "Liquidity addition failed");
        
        // Update state
        unchecked {
            totalLiquidityAdded = totalLiquidityAdded + otherHalf;
            lpTokensInContract = lpTokensInContract + lpTokensReceived;
        }
    }

    function withdrawContractATC(uint256 amount) external onlyOwner nonReentrant {
        uint256 availableATC = balanceOf(address(this)) - atcForLiquidity; // Exclude tax-allocated ATC
        require(amount > 0 && amount <= availableATC, "Invalid amount");
        
        super._update(address(this), owner(), amount);
    }

    function addCustomLiquidity(uint256 atcAmount, uint256 bnbAmount) external onlyOwner nonReentrant whenNotPaused {
        uint256 availableATC = balanceOf(address(this)) - atcForLiquidity;
        uint256 availableBNB = address(this).balance;
        
        require(atcAmount > 0 && atcAmount <= availableATC, "Invalid ATC amount");
        require(bnbAmount > 0 && bnbAmount <= availableBNB, "Invalid BNB amount");
        
        // Add liquidity with custom amounts
        (bool success, uint256 lpTokensReceived) = _addLiquidity(atcAmount, bnbAmount);
        require(success, "Liquidity addition failed");
        
        // Update state
        unchecked {
            totalLiquidityAdded = totalLiquidityAdded + atcAmount;
            lpTokensInContract = lpTokensInContract + lpTokensReceived;
        }
    }
    
    // ======== Emission Logic ========
    function _updateEmission() private {
        uint256 currentDay = block.timestamp / 1 days;
        
        // Use memoized value if already calculated today
        if (currentDay == _lastEmissionUpdateDay) {
            dailyEmission = _memoizedDailyEmission;
            return;
        }
        
        if (currentDay > lastEmissionDay) {
            // Calculate emission based on new schedule
            if (currentDay <= 365) {
                // Phase 1: Graduated start (month-based)
                uint256 month = ((currentDay - 1) / 30) + 1;
                if (month > 12) month = 12;
                dailyEmission = month * 100 * 10**18;
            } else if (currentDay <= 1825) {
                // Phase 2: Stability plateau
                dailyEmission = 1500 * 10**18;
            } else if (currentDay <= 3650) {
                // Phase 3: Growth peak
                uint256 yearInPhase = ((currentDay - 1825) / 365) + 1;
                if (yearInPhase == 1) dailyEmission = 2000 * 10**18;
                else if (yearInPhase == 2) dailyEmission = 2500 * 10**18;
                else if (yearInPhase == 3) dailyEmission = 3000 * 10**18;
                else if (yearInPhase == 4) dailyEmission = 3500 * 10**18;
                else dailyEmission = 4000 * 10**18;
            } else if (currentDay <= 5840) {
                // Phase 4: Controlled decline
                uint256 yearInPhase = ((currentDay - 3650) / 365) + 1;
                if (yearInPhase == 1) dailyEmission = 3500 * 10**18;
                else if (yearInPhase == 2) dailyEmission = 3000 * 10**18;
                else if (yearInPhase == 3) dailyEmission = 2500 * 10**18;
                else if (yearInPhase == 4) dailyEmission = 2000 * 10**18;
                else if (yearInPhase == 5) dailyEmission = 1500 * 10**18;
                else dailyEmission = 1200 * 10**18;
            } else {
                // Phase 5: Ultra-sound money with exponential decay
                uint256 daysSincePhase5 = currentDay - 5840;
                uint256 startEmission = 1000 * 10**18;
                
                // 0.01% daily decay
                uint256 decayFactor = _pow(999900 * 10**18 / 1000000, daysSincePhase5, 10**18);
                uint256 newEmission = (startEmission * decayFactor) / 10**18;
                
                // Enforce minimum
                dailyEmission = newEmission < 100 * 10**18 ? 100 * 10**18 : newEmission;
            }
            
            lastEmissionDay = currentDay;
            emittedToday = 0;
            
            // Memoize the result
            _lastEmissionUpdateDay = currentDay;
            _memoizedDailyEmission = dailyEmission;
            
            emit EmissionUpdated(dailyEmission, currentDay);
        }
    }
    
    // ======== Utility Functions ========
    function burn(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Zero amount");
        _burn(_msgSender(), amount);  // This already emits Transfer event
        emit TokensBurned(_msgSender(), amount);
    }
    
    function _pow(uint256 base, uint256 exponent, uint256 precision) private pure returns (uint256) {
        if (exponent == 0) return precision;
        
        uint256 result = precision;
        uint256 exp = exponent;
        
        while (exp > 0) {
            if (exp % 2 == 1) {
                result = (result * base) / precision;
            }
            base = (base * base) / precision;
            exp >>= 1;
            
            // Prevent underflow
            if (result < (MIN_EMISSION * precision) / PHASE2_PEAK) {
                return (MIN_EMISSION * precision) / PHASE2_PEAK;
            }
        }
        
        return result;
    }
    
    function _min(uint256 a, uint256 b, uint256 c) private pure returns (uint256) {
        uint256 minAB = a < b ? a : b;
        return minAB < c ? minAB : c;
    }
    
    // ======== View Functions ========
    function getEmissionInfo() external view returns (
        uint256 currentDailyEmission,
        uint256 emittedTodayAmount,
        uint256 availableEmission,
        uint256 currentPhase,
        uint256 daysSinceLaunch
    ) {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 available = dailyEmission > emittedToday ? 
            dailyEmission - emittedToday : 0;
        
        uint256 phase;
        if (currentDay <= 365) {
            phase = 1;
        } else if (currentDay <= 1825) {
            phase = 2;
        } else if (currentDay <= 3650) {
            phase = 3;
        } else if (currentDay <= 5840) {
            phase = 4;
        } else {
            phase = 5;
        }
        
        return (
            dailyEmission,
            emittedToday,
            available,
            phase,
            currentDay
        );
    }
    
    function getLiquidityInfo() external view returns (
        uint256 atcPendingLiquidity,
        uint256 totalLiquidityAddedSoFar,
        uint256 remainingLiquidityCapacity
    ) {
        uint256 remaining = totalLiquidityAdded >= MAX_LIQUIDITY ? 
            0 : MAX_LIQUIDITY - totalLiquidityAdded;
            
        return (
            atcForLiquidity,
            totalLiquidityAdded,
            remaining
        );
    }
    
    function isBlacklisted(address account) external view returns (bool) {
        return _isBlacklisted[account];
    }
    
    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }
}