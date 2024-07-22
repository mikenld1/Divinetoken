// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // Add ReentrancyGuard

interface IPancakeFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IPancakeRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

/**
 * @title DivineQuantaToken
 * @dev Custom ERC20 token with transaction limits, cooldowns in blocks, and owner privileges for configuration.
 */
contract DivineQuantaToken is ERC20, Ownable, ReentrancyGuard { // Use ReentrancyGuard
    uint256 public constant MAX_SUPPLY = 10 * 10**9 * 10**18; // 10 billion tokens with 18 decimals
    uint256 public constant MAX_TRANSACTION_COOLDOWN = 5; // 5 blocks

    uint256 public maxTransactionAmount = (MAX_SUPPLY * 1) / 1000; // 0.1% of total supply
    string public tokenURI;
    uint256 public transactionCooldown = MAX_TRANSACTION_COOLDOWN;
    
    mapping(address => bool) public liquidityPairs; // Mapping to track liquidity pairs
    address public INITIAL_LIQUIDITY_PAIR; // Track initial liquidity pair
    address[] private exemptedAddresses; // List of exempted addresses
    mapping(address => uint256) private lastTransactionBlock; // Last transaction block for cooldown enforcement
    mapping(address => bool) public exemptFromLimit; // Exemption list for addresses not subject to transaction limit
    bool private _initialMintingDone = false; // Flag to ensure no further minting after initial mint

    // Define events for logging
    event MaxTransactionAmountUpdated(uint256 newMaxTransactionAmount);
    event ExemptionStatusUpdated(address indexed wallet, bool isExempt);
    event TransactionCooldownUpdated(uint256 newCooldown);
    event LiquidityPairCreated(string dexName, address indexed pair);

    /**
     * @dev Sets the name, symbol, and initial supply of the token. Exempts the deployer from transaction limits.
     */
    constructor() ERC20("Divine Quanta Token", "DQT") Ownable(msg.sender) {
        _mintInitialSupply(msg.sender, MAX_SUPPLY);
        tokenURI = "https://divinequanta.com/devine.json";
        exemptFromLimit[msg.sender] = true;
        _initialMintingDone = true;
        
        // Pancakeswap mainnet router address
        IPancakeRouter PANCAKE_ROUTER = IPancakeRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        
        // Creating liquidity pair for CURRENT TOKEN/WBNB
        address liquidityPair = IPancakeFactory(PANCAKE_ROUTER.factory()).createPair(address(this), PANCAKE_ROUTER.WETH());
        liquidityPairs[liquidityPair] = true;
        INITIAL_LIQUIDITY_PAIR = liquidityPair;
        
        emit LiquidityPairCreated("PancakeSwap", liquidityPair);
    }

    /**
     * @dev Internal function to mint the initial supply. Can only be called once.
     * @param account The account to receive the initial supply.
     * @param amount The amount to mint.
     */
    function _mintInitialSupply(address account, uint256 amount) private {
        require(!_initialMintingDone, "Initial minting already done");
        _mint(account, amount);
    }

    /**
     * @dev Overrides the transfer function to include transaction limits and cooldown.
     * @param recipient The address receiving the tokens.
     * @param amount The amount of tokens to transfer.
     * @return bool indicating the success of the transfer.
     */
    function transfer(address recipient, uint256 amount) public override nonReentrant returns (bool) { // Add nonReentrant
        _applyTransferLimits(msg.sender, recipient, amount);
        return super.transfer(recipient, amount);
    }

    /**
     * @dev Overrides the transferFrom function to include transaction limits and cooldown.
     * @param sender The address sending the tokens.
     * @param recipient The address receiving the tokens.
     * @param amount The amount of tokens to transfer.
     * @return bool indicating the success of the transfer.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public override nonReentrant returns (bool) { // Add nonReentrant
        _applyTransferLimits(sender, recipient, amount);
        return super.transferFrom(sender, recipient, amount);
    }

    /**
     * @dev Applies transaction limits and cooldowns.
     * @param sender The address sending the tokens.
     * @param recipient The address receiving the tokens.
     * @param amount The amount of tokens to transfer.
     */
    function _applyTransferLimits(address sender, address recipient, uint256 amount) private {
        if (!exemptFromLimit[sender] && !exemptFromLimit[recipient]) {
       
            require(amount <= maxTransactionAmount, "Transfer exceeds the max allowed amount per transaction.");
        
            if (!liquidityPairs[recipient]) {
                require(block.number >= lastTransactionBlock[recipient] + transactionCooldown, "Recipient cooldown period not met.");
                lastTransactionBlock[recipient] = block.number;
            }

            if (!liquidityPairs[sender]) {
                require(block.number >= lastTransactionBlock[sender] + transactionCooldown, "Sender cooldown period not met.");
                lastTransactionBlock[sender] = block.number;
            }
        }
    }

    /**
     * @dev Allows the owner to update the maximum transaction amount.
     * @param _maxTxAmount The new maximum transaction amount.
     */
    function updateMaxTransactionAmount(uint256 _maxTxAmount) public onlyOwner {
        require(_maxTxAmount >= (MAX_SUPPLY * 1) / 1000, "New max transaction amount is below the minimum limit.");
        maxTransactionAmount = _maxTxAmount;
        emit MaxTransactionAmountUpdated(_maxTxAmount);
    }

    /**
     * @dev Allows the owner to exempt an address from transaction and wallet limits.
     * @param _address The address to exempt.
     * @param _status The exemption status (true or false).
     */
    function setExemptFromLimit(address _address, bool _status) public onlyOwner {
        if (_status && !exemptFromLimit[_address]) {
            exemptedAddresses.push(_address);
        } else if (!_status && exemptFromLimit[_address]) {
            for (uint256 i = 0; i < exemptedAddresses.length; i++) {
                if (exemptedAddresses[i] == _address) {
                    exemptedAddresses[i] = exemptedAddresses[exemptedAddresses.length - 1];
                    exemptedAddresses.pop();
                    break;
                }
            }
        }
        exemptFromLimit[_address] = _status;
        emit ExemptionStatusUpdated(_address, _status);
    }

    /**
     * @dev Allows the owner to update the transaction cooldown period.
     * @param cooldownInBlocks The new cooldown period in blocks.
     */
    function setTransactionCooldown(uint256 cooldownInBlocks) public onlyOwner {
        require(cooldownInBlocks <= MAX_TRANSACTION_COOLDOWN, "New cooldown period exceeds the maximum limit.");
        transactionCooldown = cooldownInBlocks;
        emit TransactionCooldownUpdated(cooldownInBlocks);
    }

    /**
     * @dev Function to add a new liquidity pair. Once added, it cannot be removed or changed.
     * @param newPair The new liquidity pair address to add.
     */
    function addNewPair(address newPair, bool status) public onlyOwner {
        require(newPair != INITIAL_LIQUIDITY_PAIR, "Error");
        liquidityPairs[newPair] = status;
    }

    /**
     * @dev Returns token metadata.
     * @return name, symbol, decimals, description, and logo URI.
     */
    function getTokenMetadata() public view returns (string memory, string memory, uint8, string memory, string memory) {
        return (name(), symbol(), decimals(), "Divine Quanta Token", "https://divinequanta.com/devinelogo.png");
    }

    /**
     * @dev Returns the total supply of the token.
     * @return The total supply of the token.
     */
    function getTotalSupply() public view returns (uint256) {
        return totalSupply();
    }

    /**
     * @dev Returns the maximum transaction amount.
     * @return The maximum transaction amount.
     */
    function getMaxTransactionAmount() public view returns (uint256) {
        return maxTransactionAmount;
    }

    /**
     * @dev Returns the transaction cooldown period.
     * @return The transaction cooldown period in blocks.
     */
    function getTransactionCooldown() public view returns (uint256) {
        return transactionCooldown;
    }

    /**
     * @dev Returns the list of exempted addresses.
     * @return The list of exempted addresses.
     */
    function getExemptedAddresses() public view returns (address[] memory) {
        return exemptedAddresses;
    }

    /**
     * @dev Returns the owner's address.
     * @return The owner's address.
     */
    function getOwner() public view returns (address) {
        return owner();
    }
}
