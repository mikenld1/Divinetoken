// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DivineQuantaToken
 * @dev Custom ERC20 token with transaction limits, cooldowns, and owner privileges for configuration.
 */
contract DivineQuantaToken is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 10 * 10**9 * 10**18; // 10 billion tokens with 18 decimals
    uint256 public constant MIN_WALLET_LIMIT = (MAX_SUPPLY * 1) / 1000; // 0.1% of total supply
    uint256 public constant MAX_TRANSACTION_COOLDOWN = 60; // 60 seconds

    uint256 public maxTransactionAmount = (MAX_SUPPLY * 1) / 1000; // 0.1% of total supply
    string public tokenURI;
    uint256 public transactionCooldown = MAX_TRANSACTION_COOLDOWN;

    address[] private exemptedAddresses; // List of exempted addresses
    mapping(address => uint256) public walletLimit; // Limits for each wallet
    mapping(address => uint256) private lastTransactionTime; // Last transaction timestamp for cooldown enforcement
    mapping(address => bool) public exemptFromLimit; // Exemption list for addresses not subject to transaction limit
    bool private immutable _initialMintingDone; // Flag to ensure no further minting after initial mint

    // Define events for logging
    event MaxTransactionAmountUpdated(uint256 newMaxTransactionAmount);
    event WalletLimitUpdated(address indexed wallet, uint256 newLimit);
    event ExemptionStatusUpdated(address indexed wallet, bool isExempt);
    event TransactionCooldownUpdated(uint256 newCooldown);

    /**
     * @dev Sets the name, symbol, and initial supply of the token. Exempts the deployer from transaction limits.
     */
    constructor() ERC20("Divine Quanta Token", "DQT") Ownable(msg.sender) {
        _mintInitialSupply(msg.sender, MAX_SUPPLY);
        tokenURI = "https://divinequanta.com/devine.json";
        walletLimit[msg.sender] = MAX_SUPPLY;
        exemptFromLimit[msg.sender] = true;
        _initialMintingDone = true;
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
    function transfer(address recipient, uint256 amount) public override returns (bool) {
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
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
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
        if (!exemptFromLimit[sender]) {
            require(amount <= maxTransactionAmount, "Transfer exceeds the max allowed amount per transaction.");
            require(balanceOf(recipient) + amount <= walletLimit[recipient], "Recipient wallet limit exceeded.");
            require(block.number >= lastTransactionTime[sender] + transactionCooldown, "Sender cooldown period not met.");
            require(block.number >= lastTransactionTime[recipient] + transactionCooldown, "Recipient cooldown period not met.");
            lastTransactionTime[sender] = block.number;
            lastTransactionTime[recipient] = block.number;
        }
    }

    /**
     * @dev Allows the owner to update the maximum transaction amount.
     * @param maxTxAmount The new maximum transaction amount.
     */
    function updateMaxTransactionAmount(uint256 maxTxAmount) public onlyOwner {
        require(maxTxAmount >= (MAX_SUPPLY * 1) / 1000, "New max transaction amount must be greater than or equal to 0.1% of total supply.");
        maxTransactionAmount = maxTxAmount;
        emit MaxTransactionAmountUpdated(maxTxAmount);
    }

    /**
     * @dev Allows the owner to update the wallet limit for a specific address.
     * @param addr The address to update the limit for.
     * @param limit The new wallet limit.
     */
    function updateWalletLimit(address addr, uint256 limit) public onlyOwner {
        require(limit >= MIN_WALLET_LIMIT, "New wallet limit is below the minimum limit of 0.1% of total supply.");
        walletLimit[addr] = limit;
        emit WalletLimitUpdated(addr, limit);
    }

    /**
     * @dev Allows the owner to exempt an address from transaction and wallet limits.
     * @param addr The address to exempt.
     * @param status The exemption status (true or false).
     */
    function setExemptFromLimit(address addr, bool status) public onlyOwner {
        if (status && !exemptFromLimit[addr]) {
            exemptedAddresses.push(addr);
        } else if (!status && exemptFromLimit[addr]) {
            for (uint256 i = 0; i < exemptedAddresses.length; i++) {
                if (exemptedAddresses[i] == addr) {
                    exemptedAddresses[i] = exemptedAddresses[exemptedAddresses.length - 1];
                    exemptedAddresses.pop();
                    break;
                }
            }
        }
        exemptFromLimit[addr] = status;
        emit ExemptionStatusUpdated(addr, status);
    }

    /**
     * @dev Allows the owner to update the transaction cooldown period.
     * @param cooldownInBlocks The new cooldown period in blocks.
     */
    function setTransactionCooldown(uint256 cooldownInBlocks) public onlyOwner {
        require(cooldownInBlocks <= MAX_TRANSACTION_COOLDOWN, "New cooldown period exceeds the maximum limit of 60 seconds.");
        transactionCooldown = cooldownInBlocks;
        emit TransactionCooldownUpdated(cooldownInBlocks);
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
     * @dev Returns the wallet limit for a specific address.
     * @param addr The address to query.
     * @return The wallet limit for the address.
     */
    function getWalletLimit(address addr) public view returns (uint256) {
        return walletLimit[addr];
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
