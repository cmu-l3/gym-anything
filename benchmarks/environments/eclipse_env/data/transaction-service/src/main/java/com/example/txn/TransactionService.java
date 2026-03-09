package com.example.txn;

import com.example.txn.model.*;
import com.example.txn.repository.AccountRepository;
import com.example.txn.repository.TransactionRepository;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Core business logic for processing financial transactions.
 * Handles deposits, withdrawals, transfers, and fee management.
 */
public class TransactionService {

    private final TransactionRepository transactionRepository;
    private final AccountRepository accountRepository;
    private final FeeCalculator feeCalculator;
    private final TransactionValidator validator;

    public TransactionService(TransactionRepository transactionRepository,
                               AccountRepository accountRepository,
                               FeeCalculator feeCalculator,
                               TransactionValidator validator) {
        this.transactionRepository = transactionRepository;
        this.accountRepository = accountRepository;
        this.feeCalculator = feeCalculator;
        this.validator = validator;
    }

    /**
     * Process a deposit to an account.
     * @return the completed transaction
     */
    public Transaction deposit(String accountId, BigDecimal amount, String description) {
        Account account = accountRepository.findById(accountId)
            .orElseThrow(() -> new IllegalArgumentException("Account not found: " + accountId));

        Transaction txn = new Transaction(UUID.randomUUID().toString(), accountId, accountId,
            amount, TransactionType.DEPOSIT);
        txn.setDescription(description);

        validator.validate(txn, account, account);

        account.setBalance(account.getBalance().add(amount));
        accountRepository.save(account);

        txn.setStatus(TransactionStatus.COMPLETED);
        return transactionRepository.save(txn);
    }

    /**
     * Process a withdrawal from an account.
     * @return the completed transaction
     */
    public Transaction withdraw(String accountId, BigDecimal amount, String description) {
        Account account = accountRepository.findById(accountId)
            .orElseThrow(() -> new IllegalArgumentException("Account not found: " + accountId));

        Transaction txn = new Transaction(UUID.randomUUID().toString(), accountId, null,
            amount, TransactionType.WITHDRAWAL);
        txn.setDescription(description);

        validator.validate(txn, account, null);

        // Calculate and deduct withdrawal fee
        BigDecimal fee = feeCalculator.calculateFee(account, TransactionType.WITHDRAWAL, amount);
        BigDecimal totalDeduction = amount.add(fee);

        if (account.getBalance().compareTo(totalDeduction) < 0) {
            txn.setStatus(TransactionStatus.FAILED);
            txn.setFailureReason("Insufficient balance to cover withdrawal + fee");
            return transactionRepository.save(txn);
        }

        account.setBalance(account.getBalance().subtract(totalDeduction));
        accountRepository.save(account);

        txn.setStatus(TransactionStatus.COMPLETED);
        return transactionRepository.save(txn);
    }

    /**
     * Transfer funds between two accounts.
     * @return the completed transfer transaction
     */
    public Transaction transfer(String fromAccountId, String toAccountId,
                                 BigDecimal amount, String description) {
        Account fromAccount = accountRepository.findById(fromAccountId)
            .orElseThrow(() -> new IllegalArgumentException("Source account not found: " + fromAccountId));
        Account toAccount = accountRepository.findById(toAccountId)
            .orElseThrow(() -> new IllegalArgumentException("Destination account not found: " + toAccountId));

        Transaction txn = new Transaction(UUID.randomUUID().toString(), fromAccountId, toAccountId,
            amount, TransactionType.TRANSFER);
        txn.setDescription(description);

        validator.validate(txn, fromAccount, toAccount);

        BigDecimal fee = feeCalculator.calculateFee(fromAccount, TransactionType.TRANSFER, amount);

        // Deduct amount + fee from source
        fromAccount.setBalance(fromAccount.getBalance().subtract(amount).subtract(fee));
        // Credit amount to destination (fee not applied to recipient)
        toAccount.setBalance(toAccount.getBalance().add(amount));

        accountRepository.save(fromAccount);
        accountRepository.save(toAccount);

        txn.setStatus(TransactionStatus.COMPLETED);
        return transactionRepository.save(txn);
    }

    /**
     * Reverse a completed transaction (refund).
     * @return the reversed transaction
     */
    public Transaction reverse(String transactionId) {
        Transaction original = transactionRepository.findById(transactionId)
            .orElseThrow(() -> new IllegalArgumentException("Transaction not found: " + transactionId));

        if (original.getStatus() != TransactionStatus.COMPLETED)
            throw new IllegalStateException("Only COMPLETED transactions can be reversed");

        Account fromAccount = accountRepository.findById(original.getFromAccountId())
            .orElseThrow(() -> new IllegalArgumentException("Account not found"));

        // Reverse the balance change
        if (original.getType() == TransactionType.DEPOSIT) {
            fromAccount.setBalance(fromAccount.getBalance().subtract(original.getAmount()));
        } else if (original.getType() == TransactionType.WITHDRAWAL) {
            fromAccount.setBalance(fromAccount.getBalance().add(original.getAmount()));
        }

        accountRepository.save(fromAccount);
        original.setStatus(TransactionStatus.REVERSED);
        return transactionRepository.save(original);
    }

    /**
     * Get transaction history for an account.
     */
    public List<Transaction> getTransactionHistory(String accountId) {
        accountRepository.findById(accountId)
            .orElseThrow(() -> new IllegalArgumentException("Account not found: " + accountId));
        return transactionRepository.findByAccountId(accountId);
    }

    /**
     * Get account balance.
     */
    public BigDecimal getBalance(String accountId) {
        Account account = accountRepository.findById(accountId)
            .orElseThrow(() -> new IllegalArgumentException("Account not found: " + accountId));
        return account.getBalance();
    }
}
