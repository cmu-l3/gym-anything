package com.bank.processing;

import com.bank.commons.Account;
import com.bank.commons.Transaction;
import com.bank.ledger.BalanceCalculator;
import com.bank.ledger.Ledger;
import com.bank.ledger.LedgerEntry;

import org.junit.Before;
import org.junit.Test;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

import static org.junit.Assert.*;

/**
 * Tests for transaction processing and batch operations.
 */
public class ProcessingTest {

    private Ledger ledger;
    private BalanceCalculator calculator;
    private Map<String, Account> accounts;
    private TransactionProcessor processor;

    @Before
    public void setUp() {
        ledger = new Ledger();
        calculator = new BalanceCalculator(ledger);

        accounts = new HashMap<>();
        accounts.put("ACC001", new Account("ACC001", "Alice Johnson"));
        accounts.put("ACC002", new Account("ACC002", "Bob Smith"));
        accounts.put("ACC003", new Account("ACC003", "Charlie Brown"));

        processor = new TransactionProcessor(ledger, calculator, accounts);

        // Fund accounts with initial deposits
        processor.processDeposit(
                new Transaction("INIT1", null, "ACC001", 1000.00, Transaction.Type.DEPOSIT));
        processor.processDeposit(
                new Transaction("INIT2", null, "ACC002", 2000.00, Transaction.Type.DEPOSIT));
    }

    // --- Tests that pass after compilation fix (no balance dependency) ---

    @Test
    public void testDepositToClosedAccount() {
        accounts.get("ACC003").setStatus(Account.Status.CLOSED);
        Transaction tx = new Transaction("TX_DEP", null, "ACC003", 500.00, Transaction.Type.DEPOSIT);

        assertFalse("Deposit to closed account should fail", processor.processDeposit(tx));
        assertEquals(Transaction.Status.FAILED, tx.getStatus());
    }

    // --- Tests that pass after Bug 2 is fixed (BalanceCalculator filter) ---

    @Test
    public void testDepositAndCheckBalance() {
        Transaction tx = new Transaction("TX_DEP", null, "ACC003", 500.00, Transaction.Type.DEPOSIT);
        assertTrue("Deposit should succeed", processor.processDeposit(tx));

        // ACC003 should have exactly 500 (not mixed with ACC001/ACC002 balances)
        assertEquals(500.00, calculator.getBalance("ACC003"), 0.01);
    }

    @Test
    public void testSuccessfulTransfer() {
        Transaction tx = new Transaction("TX001", "ACC001", "ACC002", 300.00,
                Transaction.Type.TRANSFER);
        boolean result = processor.processTransfer(tx);

        assertTrue("Transfer should succeed", result);
        assertEquals(Transaction.Status.COMPLETED, tx.getStatus());
        assertEquals(700.00, calculator.getBalance("ACC001"), 0.01);
        assertEquals(2300.00, calculator.getBalance("ACC002"), 0.01);
    }

    // --- Tests that fail due to Bug 3 (TransactionProcessor atomicity) ---

    @Test
    public void testTransferToFrozenAccountLeavesSourceUnchanged() {
        accounts.get("ACC002").setStatus(Account.Status.FROZEN);
        Transaction tx = new Transaction("TX002", "ACC001", "ACC002", 100.00,
                Transaction.Type.TRANSFER);

        boolean result = processor.processTransfer(tx);

        assertFalse("Transfer to frozen account should fail", result);
        assertEquals(Transaction.Status.FAILED, tx.getStatus());
        // Source balance must be unchanged — no debit should have occurred
        assertEquals(1000.00, calculator.getBalance("ACC001"), 0.01);
    }

    @Test
    public void testTransferToNonexistentAccountLeavesSourceUnchanged() {
        Transaction tx = new Transaction("TX003", "ACC001", "ACC_BOGUS", 200.00,
                Transaction.Type.TRANSFER);

        boolean result = processor.processTransfer(tx);

        assertFalse("Transfer to nonexistent account should fail", result);
        // Source balance must be unchanged
        assertEquals(1000.00, calculator.getBalance("ACC001"), 0.01);
    }

    @Test
    public void testTransferExceedingBalanceIsRejected() {
        Transaction tx = new Transaction("TX004", "ACC001", "ACC002", 5000.00,
                Transaction.Type.TRANSFER);

        boolean result = processor.processTransfer(tx);

        assertFalse("Transfer exceeding balance should fail", result);
        assertEquals(Transaction.Status.FAILED, tx.getStatus());
        // Both balances must be unchanged
        assertEquals(1000.00, calculator.getBalance("ACC001"), 0.01);
        assertEquals(2000.00, calculator.getBalance("ACC002"), 0.01);
    }

    @Test
    public void testBatchWithMixedResults() {
        accounts.get("ACC003").setStatus(Account.Status.FROZEN);
        BatchProcessor batch = new BatchProcessor(processor);

        BatchProcessor.BatchResult result = batch.processBatch(Arrays.asList(
                // Should succeed: valid deposit
                new Transaction("B001", null, "ACC001", 100.00, Transaction.Type.DEPOSIT),
                // Should fail: transfer to frozen account
                new Transaction("B002", "ACC001", "ACC003", 50.00, Transaction.Type.TRANSFER),
                // Should succeed: valid transfer
                new Transaction("B003", "ACC001", "ACC002", 200.00, Transaction.Type.TRANSFER)
        ));

        assertEquals("Two transactions should succeed", 2, result.getSucceeded());
        assertEquals("One transaction should fail", 1, result.getFailed());
        assertTrue("Failed list should contain B002",
                result.getFailedTransactionIds().contains("B002"));

        // Verify final balances reflect only the successful operations
        // ACC001: 1000 (init) + 100 (deposit) - 200 (transfer) = 900
        assertEquals(900.00, calculator.getBalance("ACC001"), 0.01);
        // ACC002: 2000 (init) + 200 (transfer) = 2200
        assertEquals(2200.00, calculator.getBalance("ACC002"), 0.01);
    }
}
