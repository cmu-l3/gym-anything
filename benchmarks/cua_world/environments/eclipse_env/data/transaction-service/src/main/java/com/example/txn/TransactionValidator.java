package com.example.txn;

import com.example.txn.model.Account;
import com.example.txn.model.Transaction;
import com.example.txn.model.TransactionType;

import java.math.BigDecimal;

/**
 * Validates transactions before processing.
 * Contains business rules for all transaction types.
 */
public class TransactionValidator {

    private static final BigDecimal MAX_TRANSFER_AMOUNT = new BigDecimal("50000.00");
    private static final BigDecimal MIN_TRANSACTION_AMOUNT = new BigDecimal("0.01");

    /**
     * Validate a transaction. Throws IllegalArgumentException if invalid.
     */
    public void validate(Transaction transaction, Account fromAccount, Account toAccount) {
        if (transaction == null) throw new IllegalArgumentException("Transaction must not be null");
        if (transaction.getAmount() == null)
            throw new IllegalArgumentException("Amount must not be null");
        if (transaction.getAmount().compareTo(MIN_TRANSACTION_AMOUNT) < 0)
            throw new IllegalArgumentException("Amount must be at least " + MIN_TRANSACTION_AMOUNT);

        if (!fromAccount.isActive())
            throw new IllegalArgumentException("Source account is not active");

        switch (transaction.getType()) {
            case DEPOSIT:
                validateDeposit(transaction, toAccount);
                break;
            case WITHDRAWAL:
                validateWithdrawal(transaction, fromAccount);
                break;
            case TRANSFER:
                validateTransfer(transaction, fromAccount, toAccount);
                break;
            case FEE_CHARGE:
                validateFeeCharge(transaction, fromAccount);
                break;
            default:
                throw new IllegalArgumentException("Unknown transaction type: " + transaction.getType());
        }
    }

    private void validateDeposit(Transaction txn, Account toAccount) {
        if (toAccount == null) throw new IllegalArgumentException("Destination account required for deposit");
        if (!toAccount.isActive()) throw new IllegalArgumentException("Destination account is not active");
    }

    private void validateWithdrawal(Transaction txn, Account fromAccount) {
        if (fromAccount.getBalance().compareTo(txn.getAmount()) < 0)
            throw new IllegalArgumentException("Insufficient balance for withdrawal");
    }

    private void validateTransfer(Transaction txn, Account from, Account to) {
        if (to == null) throw new IllegalArgumentException("Destination account required for transfer");
        if (!to.isActive()) throw new IllegalArgumentException("Destination account is not active");
        if (from.getBalance().compareTo(txn.getAmount()) < 0)
            throw new IllegalArgumentException("Insufficient balance for transfer");
        if (txn.getAmount().compareTo(MAX_TRANSFER_AMOUNT) > 0)
            throw new IllegalArgumentException("Transfer amount exceeds maximum allowed: " + MAX_TRANSFER_AMOUNT);
    }

    private void validateFeeCharge(Transaction txn, Account fromAccount) {
        if (fromAccount.getBalance().compareTo(txn.getAmount()) < 0)
            throw new IllegalArgumentException("Insufficient balance for fee charge");
    }
}
