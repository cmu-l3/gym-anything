package com.example.txn;

import com.example.txn.model.Account;
import com.example.txn.model.AccountType;
import com.example.txn.repository.AccountRepository;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

/**
 * Service for managing bank accounts.
 */
public class AccountService {

    private final AccountRepository accountRepository;

    public AccountService(AccountRepository accountRepository) {
        this.accountRepository = accountRepository;
    }

    /**
     * Open a new account.
     */
    public Account openAccount(String ownerId, String accountNumber,
                                BigDecimal initialBalance, AccountType type) {
        if (accountNumber == null || accountNumber.isBlank())
            throw new IllegalArgumentException("Account number required");
        if (initialBalance == null || initialBalance.compareTo(BigDecimal.ZERO) < 0)
            throw new IllegalArgumentException("Initial balance cannot be negative");

        accountRepository.findByAccountNumber(accountNumber).ifPresent(a -> {
            throw new IllegalStateException("Account number already exists: " + accountNumber);
        });

        Account account = new Account(UUID.randomUUID().toString(), ownerId,
            accountNumber, initialBalance, type);
        return accountRepository.save(account);
    }

    /**
     * Close an account (marks as inactive).
     */
    public Account closeAccount(String accountId) {
        Account account = accountRepository.findById(accountId)
            .orElseThrow(() -> new IllegalArgumentException("Account not found: " + accountId));
        if (!account.isActive())
            throw new IllegalStateException("Account is already closed");
        if (account.getBalance().compareTo(BigDecimal.ZERO) > 0)
            throw new IllegalStateException("Cannot close account with positive balance");
        account.setActive(false);
        return accountRepository.save(account);
    }

    /**
     * Get all accounts for an owner.
     */
    public List<Account> getAccountsByOwner(String ownerId) {
        return accountRepository.findByOwnerId(ownerId);
    }
}
