// SPDX-License-Identifier: MIT

//  alex new code with hooks

pragma solidity ^0.8.0;
import
"@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import
"@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
contract EnhancedAICryptoTradingBot is ReentrancyGuard, Pausable, Ownable
{
using SafeERC20 for IERC20;
uint256 public constant MAX_SLIPPAGE = 50;
uint256 public constant DEADLINE_BUFFER = 300;
uint256 public constant PRICE_STALENESS_THRESHOLD = 3600;
IUniswapV2Router02 public immutable uniswapRouter;
uint256 public slippagePercent = 2;
mapping(address => bool) public whitelistedTokens;
mapping(address => address) public tokenPriceFeeds;
mapping(address => uint256) public lastTxBlock;
struct Trade {
address token;
uint256 amountIn;
uint256 amountOut;
uint256 timestamp;
bool isETHToToken;
bool isAITrade;
string metadata;
}
Trade[] public tradeHistory;
uint256 public totalTrades;
event TradeExecuted(address indexed token, uint256 amountIn, uint256
amountOut, uint256 timestamp, bool isETHToToken);
event AITradeTriggered(address indexed token, bool isBuy, uint256
amount, string metadata);
event AIStrategyUpdated(uint256 newSlippage, string reason);
event ChainlinkStalePrice(address indexed priceFeed, uint256
updatedAt, uint256 currentTime);
event TokensWithdrawn(address indexed token, uint256 amount);
event ETHWithdrawn(uint256 amount);
event TokenWhitelisted(address indexed token, address priceFeed);
event TokenBlacklisted(address indexed token);
event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
event EmergencyWithdrawal(address indexed token, uint256 amount);
modifier antiMEV() {
one tx per block allowed");
;
_
require(lastTxBlock[msg.sender] < block.number, "Anti-MEV: Only
lastTxBlock[msg.sender] = block.number;
}
constructor(address _router) Ownable(msg.sender) {
require(_router != address(0), "Invalid router address");
uniswapRouter = IUniswapV2Router02(_router);
}
receive() external payable {}
function getLatestPrice(address priceFeedAddress) public view returns
(uint256) {
address");
require(priceFeedAddress != address(0), "Invalid price feed
try AggregatorV3Interface(priceFeedAddress).latestRoundData()
returns (
uint80, int256 answer, uint256, uint256 updatedAt, uint80
) {
require(answer > 0, "Invalid price");
if (block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) {
revert("Price data is stale");
}
return uint256(answer);
} catch {
revert("Invalid Chainlink feed or stale data");
}
}
function _handleStalePrice(address priceFeedAddress, uint256
updatedAt) internal {
emit ChainlinkStalePrice(priceFeedAddress, updatedAt,
block.timestamp);
if (block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) {
_pause();
revert("Price data is stale");
}
}
function setSlippagePercent(uint256 _slippage) external onlyOwner {
require(_slippage <= MAX_SLIPPAGE, "Slippage too high");
uint256 old = slippagePercent;
slippagePercent = _slippage;
emit SlippageUpdated(old, _slippage);
}
function aiUpdateSlippage(uint256 newSlippage, string memory reason)
external onlyOwner {
require(newSlippage <= MAX_SLIPPAGE, "Too high");
uint256 old = slippagePercent;
slippagePercent = newSlippage;
emit SlippageUpdated(old, newSlippage);
emit AIStrategyUpdated(newSlippage, reason);
}
function whitelistToken(address token, address priceFeed) external
onlyOwner {
address");
require(token != address(0) && priceFeed != address(0), "Invalid
getLatestPrice(priceFeed);
whitelistedTokens[token] = true;
tokenPriceFeeds[token] = priceFeed;
emit TokenWhitelisted(token, priceFeed);
}
function blacklistToken(address token) external onlyOwner {
whitelistedTokens[token] = false;
delete tokenPriceFeeds[token];
emit TokenBlacklisted(token);
}
function _validatePath(address[] memory path, address token, bool
isETHToToken) private view {
require(path.length >= 2, "Invalid path");
if (isETHToToken) {
require(path[0] == uniswapRouter.WETH() && path[path.length -
1] == token, "Invalid ETH->Token path");
} else {
require(path[0] == token && path[path.length - 1] ==
uniswapRouter.WETH(), "Invalid Token->ETH path");
}
}
function _calculateMinOut(uint256 expectedAmount) private view returns
(uint256) {
return (expectedAmount * (100 - slippagePercent)) / 100;
}
function aiSwapETHForTokens(address token, address[] memory path,
uint256 maxPriceImpact, string memory metadata)
external payable onlyOwner nonReentrant whenNotPaused antiMEV
{
require(msg.value > 0 && whitelistedTokens[token], "Invalid
swap");
require(maxPriceImpact <= 1000, "Max price impact exceeded");
_validatePath(path, token, true);
uint256[] memory out = uniswapRouter.getAmountsOut(msg.value,
path);
uint256 minOut = _calculateMinOut(out[out.length - 1]);
uint256[] memory result =
uniswapRouter.swapExactETHForTokens{value: msg.value}(
minOut, path, address(this), block.timestamp + DEADLINE_BUFFER
);
tradeHistory.push(Trade(token, msg.value, result[result.length -
1], block.timestamp, true, true, metadata));
totalTrades++;
emit TradeExecuted(token, msg.value, result[result.length - 1],
block.timestamp, true);
emit AITradeTriggered(token, true, msg.value, metadata);
}
function withdrawTokens(address token, uint256 amount) external
onlyOwner nonReentrant {
require(token != address(0), "Token address is zero");
uint256 balance = IERC20(token).balanceOf(address(this));
require(balance > 0, "No tokens to withdraw");
uint256 withdrawAmount = amount == 0 ? balance : amount;
require(withdrawAmount <= balance, "Withdraw exceeds balance");
IERC20(token).safeTransfer(owner(), withdrawAmount);
emit TokensWithdrawn(token, withdrawAmount);
}
function withdrawETH(uint256 amount) external onlyOwner nonReentrant {
uint256 balance = address(this).balance;
require(balance > 0, "No ETH to withdraw");
uint256 withdrawAmount = amount == 0 ? balance : amount;
require(withdrawAmount <= balance, "Withdraw exceeds balance");
(bool success, ) = payable(owner()).call{value:
withdrawAmount}("");
require(success, "ETH transfer failed");
emit ETHWithdrawn(withdrawAmount);
}
function pauseTrading() external onlyOwner {
_pause();
}
function unpauseTrading() external onlyOwner {
_unpause();
}
function emergencyWithdraw(address token) external onlyOwner
whenPaused {
if (token == address(0)) {
uint256 ethBalance = address(this).balance;
if (ethBalance > 0) {
(bool success, ) = payable(owner()).call{value:
ethBalance}("");
}
} else {
}
require(success);
emit EmergencyWithdrawal(address(0), ethBalance);
uint256 tokenBalance = IERC20(token).balanceOf(address(this));
if (tokenBalance > 0) {
IERC20(token).safeTransfer(owner(), tokenBalance);
emit EmergencyWithdrawal(token, tokenBalance);
}
}
function getTradeHistory(uint256 offset, uint256 limit) external view
returns (Trade[] memory trades) {
require(offset < tradeHistory.length);
uint256 end = offset + limit;
if (end > tradeHistory.length) end = tradeHistory.length;
trades = new Trade[](end - offset);
for (uint256 i = offset; i < end; i++) {
trades[i - offset] = tradeHistory[i];
}
}
function getBalances(address[] memory tokens) external view returns
(uint256[] memory balances) {
balances = new uint256[](tokens.length);
for (uint256 i = 0; i < tokens.length; i++) {
balances[i] = tokens[i] == address(0)
? address(this).balance
: IERC20(tokens[i]).balanceOf(address(this));
}
}
function isTokenValid(address token) external view returns (bool) {
if (!whitelistedTokens[token] || tokenPriceFeeds[token] ==
address(0)) return false;
try this.getLatestPrice(tokenPriceFeeds[token]) returns (uint256)
{
return true;
} catch {
return false;
}
}
function destroyContract() external onlyOwner whenPaused {
selfdestruct(payable(owner()));
}
}
