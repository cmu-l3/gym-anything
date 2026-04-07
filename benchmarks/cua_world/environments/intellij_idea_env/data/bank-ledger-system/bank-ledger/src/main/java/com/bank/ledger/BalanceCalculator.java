package com.bank.ledger;

import java.util.List;

/**
 * Calculates account balances from ledger entries.
 *
 * The balance for an account is computed by summing only the entries
 * that belong to that specific account. Credits increase the balance
 * and debits decrease it.
 */
public class BalanceCalculator {

    private final Ledger ledger;

    public BalanceCalculator(Ledger ledger) {
        this.ledger = ledger;
    }

    /**
     * Returns the current balance for the given account.
     *
     * Only entries belonging to the specified account should be considered.
     * The balance is: sum of all credit amounts minus sum of all debit amounts
     * for that account.
     *
     * @param accountId the account to query
     * @return the account balance
     */
    public double getBalance(String accountId) {
        double balance = 0;
        List<LedgerEntry> entries = ledger.getEntries();
        for (LedgerEntry entry : entries) {
            balance += entry.getCreditAmount() - entry.getDebitAmount();
        }
        return balance;
    }

    /**
     * Returns true if the given account has at least the specified amount available.
     *
     * @param accountId the account to check
     * @param amount    the required amount
     * @return true if the account balance is at least the given amount
     */
    public boolean hasSufficientFunds(String accountId, double amount) {
        return getBalance(accountId) >= amount;
    }
}
