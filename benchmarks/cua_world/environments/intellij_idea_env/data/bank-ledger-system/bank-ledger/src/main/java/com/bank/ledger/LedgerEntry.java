package com.bank.ledger;

import java.time.LocalDateTime;

/**
 * Represents a single entry in the double-entry ledger.
 * Each entry records either a debit or a credit against a specific account.
 *
 * In proper double-entry bookkeeping, each entry must have exactly one
 * non-zero amount: either debitAmount OR creditAmount, but never both
 * and never neither.
 */
public class LedgerEntry {

    private final String entryId;
    private final String accountId;
    private final double debitAmount;
    private final double creditAmount;
    private final String description;
    private final LocalDateTime timestamp;

    public LedgerEntry(String entryId, String accountId,
                       double debitAmount, double creditAmount, String description) {
        this.entryId = entryId;
        this.accountId = accountId;
        this.debitAmount = debitAmount;
        this.creditAmount = creditAmount;
        this.description = description;
        this.timestamp = LocalDateTime.now();
    }

    public String getEntryId() { return entryId; }
    public String getAccountId() { return accountId; }
    public double getDebitAmount() { return debitAmount; }
    public double getCreditAmount() { return creditAmount; }
    public String getDescription() { return description; }
    public LocalDateTime getTimestamp() { return timestamp; }

    /**
     * Returns the net effect of this entry on the account balance.
     * Credits increase balance (positive), debits decrease it (negative).
     */
    public double getNetAmount() {
        return creditAmount - debitAmount;
    }

    @Override
    public String toString() {
        return String.format("LedgerEntry{id='%s', account='%s', debit=%.2f, credit=%.2f, desc='%s'}",
                entryId, accountId, debitAmount, creditAmount, description);
    }
}
