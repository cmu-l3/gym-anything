package com.bank.ledger;

import org.junit.Before;
import org.junit.Test;
import static org.junit.Assert.*;

/**
 * Tests for the Ledger and BalanceCalculator components.
 */
public class LedgerTest {

    private Ledger ledger;
    private BalanceCalculator calculator;

    @Before
    public void setUp() {
        ledger = new Ledger();
        calculator = new BalanceCalculator(ledger);
    }

    // --- Basic ledger operations (pass after compilation fix) ---

    @Test
    public void testAddValidDebitEntry() {
        ledger.addEntry(new LedgerEntry("E001", "ACC001", 100.00, 0, "Valid debit"));
        assertEquals(1, ledger.getEntryCount());
    }

    @Test
    public void testEmptyAccountBalance() {
        assertEquals(0.0, calculator.getBalance("ACC001"), 0.0001);
    }

    // --- Ledger invariant tests (fail due to Bug 4: no validation) ---

    @Test(expected = IllegalArgumentException.class)
    public void testRejectEntryWithBothDebitAndCredit() {
        // An entry with BOTH debit and credit non-zero violates double-entry rules
        ledger.addEntry(new LedgerEntry("E001", "ACC001", 100.00, 50.00, "Invalid dual entry"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void testRejectEntryWithZeroAmounts() {
        // An entry with BOTH debit and credit as zero is meaningless
        ledger.addEntry(new LedgerEntry("E001", "ACC001", 0, 0, "Invalid zero entry"));
    }

    // --- Balance calculation tests (fail due to Bug 2: no accountId filter) ---

    @Test
    public void testSingleAccountBalanceWithOtherAccounts() {
        // Entries for multiple accounts
        ledger.addEntry(new LedgerEntry("E001", "ACC001", 0, 1000.00, "Deposit to ACC001"));
        ledger.addEntry(new LedgerEntry("E002", "ACC002", 0, 2000.00, "Deposit to ACC002"));
        ledger.addEntry(new LedgerEntry("E003", "ACC001", 250.00, 0, "Withdrawal from ACC001"));

        // ACC001 balance should be 1000 - 250 = 750, NOT including ACC002's entries
        assertEquals(750.00, calculator.getBalance("ACC001"), 0.01);
    }

    @Test
    public void testMultipleAccountsHaveIsolatedBalances() {
        ledger.addEntry(new LedgerEntry("E001", "ACC001", 0, 1000.00, "Deposit ACC001"));
        ledger.addEntry(new LedgerEntry("E002", "ACC002", 0, 500.00, "Deposit ACC002"));
        ledger.addEntry(new LedgerEntry("E003", "ACC003", 0, 750.00, "Deposit ACC003"));

        // Each account balance must reflect ONLY its own entries
        assertEquals(1000.00, calculator.getBalance("ACC001"), 0.01);
        assertEquals(500.00, calculator.getBalance("ACC002"), 0.01);
        assertEquals(750.00, calculator.getBalance("ACC003"), 0.01);
    }

    @Test
    public void testBalanceWithManyEntriesAcrossAccounts() {
        for (int i = 0; i < 50; i++) {
            ledger.addEntry(new LedgerEntry("EA" + i, "ACC001", 0, 10.00, "Deposit " + i));
            ledger.addEntry(new LedgerEntry("EB" + i, "ACC002", 0, 20.00, "Deposit " + i));
        }
        // ACC001: 50 * 10 = 500; ACC002: 50 * 20 = 1000
        assertEquals(500.00, calculator.getBalance("ACC001"), 0.01);
        assertEquals(1000.00, calculator.getBalance("ACC002"), 0.01);
    }

    @Test
    public void testSufficientFundsCheckWithMultipleAccounts() {
        ledger.addEntry(new LedgerEntry("E001", "ACC001", 0, 5000.00, "Deposit ACC001"));
        ledger.addEntry(new LedgerEntry("E002", "ACC002", 0, 3000.00, "Deposit ACC002"));
        ledger.addEntry(new LedgerEntry("E003", "ACC001", 1000.00, 0, "Withdrawal ACC001"));

        // ACC001 balance = 5000 - 1000 = 4000
        assertTrue(calculator.hasSufficientFunds("ACC001", 3000.00));
        assertTrue(calculator.hasSufficientFunds("ACC001", 4000.00));
        assertFalse(calculator.hasSufficientFunds("ACC001", 4500.00));
    }
}
