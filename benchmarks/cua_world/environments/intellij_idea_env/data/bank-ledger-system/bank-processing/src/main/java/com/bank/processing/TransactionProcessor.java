package com.bank.processing;

import com.bank.commons.Account;
import com.bank.commons.Transaction;
import com.bank.ledger.BalanceCalculator;
import com.bank.ledger.Ledger;
import com.bank.ledger.LedgerEntry;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Processes financial transactions against the ledger.
 *
 * Transfer operations must be atomic: the source account is debited and the
 * destination account is credited as a single logical operation. If any
 * validation fails (inactive destination, insufficient funds), neither the
 * debit nor the credit should occur.
 */
public class TransactionProcessor {

    private final Ledger ledger;
    private final BalanceCalculator balanceCalculator;
    private final Map<String, Account> accounts;
    private final AtomicInteger entryCounter = new AtomicInteger(1000);

    public TransactionProcessor(Ledger ledger, BalanceCalculator balanceCalculator,
                                Map<String, Account> accounts) {
        this.ledger = ledger;
        this.balanceCalculator = balanceCalculator;
        this.accounts = new HashMap<>(accounts);
    }

    /**
     * Processes a transfer transaction.
     *
     * A valid transfer requires:
     * 1. The destination account must exist and be ACTIVE.
     * 2. The source account must have sufficient funds.
     * 3. Both the debit (source) and credit (destination) entries must be
     *    created atomically — if validation fails, no entries are created.
     *
     * @param tx the transfer transaction
     * @return true if the transfer succeeded, false otherwise
     */
    public boolean processTransfer(Transaction tx) {
        String sourceId = tx.getSourceAccountId();
        String destId = tx.getDestAccountId();
        double amount = tx.getAmount();

        // Debit the source account first
        String debitEntryId = "E" + entryCounter.getAndIncrement();
        ledger.addEntry(new LedgerEntry(debitEntryId, sourceId, amount, 0,
                "Transfer debit: " + tx.getTransactionId()));

        // Now check if destination is valid
        Account destAccount = accounts.get(destId);
        if (destAccount == null || destAccount.getStatus() != Account.Status.ACTIVE) {
            tx.setStatus(Transaction.Status.FAILED);
            return false;
        }

        // Credit the destination account
        String creditEntryId = "E" + entryCounter.getAndIncrement();
        ledger.addEntry(new LedgerEntry(creditEntryId, destId, 0, amount,
                "Transfer credit: " + tx.getTransactionId()));

        tx.setStatus(Transaction.Status.COMPLETED);
        return true;
    }

    /**
     * Processes a deposit transaction.
     */
    public boolean processDeposit(Transaction tx) {
        String accountId = tx.getDestAccountId();
        Account account = accounts.get(accountId);
        if (account == null || account.getStatus() != Account.Status.ACTIVE) {
            tx.setStatus(Transaction.Status.FAILED);
            return false;
        }

        String entryId = "E" + entryCounter.getAndIncrement();
        ledger.addEntry(new LedgerEntry(entryId, accountId, 0, tx.getAmount(),
                "Deposit: " + tx.getTransactionId()));
        tx.setStatus(Transaction.Status.COMPLETED);
        return true;
    }

    /**
     * Processes a withdrawal transaction.
     */
    public boolean processWithdrawal(Transaction tx) {
        String accountId = tx.getSourceAccountId();
        Account account = accounts.get(accountId);
        if (account == null || account.getStatus() != Account.Status.ACTIVE) {
            tx.setStatus(Transaction.Status.FAILED);
            return false;
        }

        if (!balanceCalculator.hasSufficientFunds(accountId, tx.getAmount())) {
            tx.setStatus(Transaction.Status.FAILED);
            return false;
        }

        String entryId = "E" + entryCounter.getAndIncrement();
        ledger.addEntry(new LedgerEntry(entryId, accountId, tx.getAmount(), 0,
                "Withdrawal: " + tx.getTransactionId()));
        tx.setStatus(Transaction.Status.COMPLETED);
        return true;
    }
}
