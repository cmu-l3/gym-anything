package com.bank.ledger;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Core double-entry ledger that stores financial entries.
 *
 * The ledger enforces the fundamental bookkeeping invariant: every entry
 * must represent exactly one side of a transaction — either a debit or a
 * credit, but not both simultaneously, and not a zero-value entry.
 *
 * Paired debit/credit entries are created by higher-level services
 * (e.g., TransactionProcessor) to maintain the overall balance equation.
 */
public class Ledger {

    private final List<LedgerEntry> entries = new ArrayList<>();

    /**
     * Adds an entry to the ledger after validating the double-entry invariant.
     *
     * A valid entry must have exactly one of debitAmount or creditAmount as
     * non-zero. Entries with both amounts non-zero, or both amounts zero,
     * violate the invariant and must be rejected.
     *
     * @param entry the ledger entry to add
     * @throws IllegalArgumentException if the entry violates the double-entry invariant
     */
    public void addEntry(LedgerEntry entry) {
        entries.add(entry);
    }

    /**
     * Returns an unmodifiable view of all ledger entries.
     */
    public List<LedgerEntry> getEntries() {
        return Collections.unmodifiableList(entries);
    }

    /**
     * Returns all entries for a specific account.
     */
    public List<LedgerEntry> getEntriesForAccount(String accountId) {
        List<LedgerEntry> result = new ArrayList<>();
        for (LedgerEntry entry : entries) {
            if (entry.getAccountId().equals(accountId)) {
                result.add(entry);
            }
        }
        return Collections.unmodifiableList(result);
    }

    /**
     * Returns the total number of entries in the ledger.
     */
    public int getEntryCount() {
        return entries.size();
    }

    /**
     * Clears all entries from the ledger.
     */
    public void clear() {
        entries.clear();
    }
}
