package com.payments;

import org.junit.Test;
import static org.junit.Assert.*;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

/**
 * Tests for TransferService correctness and concurrency safety.
 */
public class TransferServiceTest {

    // -----------------------------------------------------------------------
    // Basic transfer tests
    // -----------------------------------------------------------------------

    @Test
    public void testBasicTransferMovesBalance() {
        AuditLogger logger = new AuditLogger();
        TransferService service = new TransferService(logger);

        Account alice = new Account("ACC-001", "Alice", 100_00L);   // $100.00
        Account bob   = new Account("ACC-002", "Bob",   50_00L);    // $50.00

        service.transfer(alice, bob, 25_00L);  // transfer $25

        assertEquals("Alice should have $75 after transfer",   75_00L, alice.getBalanceCents());
        assertEquals("Bob should have $75 after receiving",    75_00L, bob.getBalanceCents());
        assertEquals("One audit entry should be recorded",    1, logger.getLogCount());
    }

    @Test
    public void testTransferLogsAuditEntry() {
        AuditLogger logger = new AuditLogger();
        TransferService service = new TransferService(logger);

        Account src = new Account("SRC-1", "Source", 200_00L);
        Account dst = new Account("DST-1", "Dest",     0_00L);

        service.transfer(src, dst, 50_00L);

        List<String> entries = logger.getEntries();
        assertEquals(1, entries.size());
        assertTrue("Audit entry should mention TRANSFER", entries.get(0).contains("TRANSFER"));
        assertTrue("Audit entry should mention source ID", entries.get(0).contains("SRC-1"));
        assertTrue("Audit entry should mention dest ID",   entries.get(0).contains("DST-1"));
    }

    // -----------------------------------------------------------------------
    // Overdraft protection test (exercises Account.withdraw bug)
    // -----------------------------------------------------------------------

    @Test
    public void testTransferFailsWhenInsufficientFunds() {
        AuditLogger logger = new AuditLogger();
        TransferService service = new TransferService(logger);

        Account poor = new Account("POOR-1", "Poor", 10_00L);   // only $10
        Account rich = new Account("RICH-1", "Rich", 500_00L);

        try {
            service.transfer(poor, rich, 50_00L);  // attempt to send $50 when only $10 available
            fail("Expected an exception when withdrawing more than available balance, " +
                 "but no exception was thrown. Account.withdraw() must check for insufficient funds.");
        } catch (IllegalStateException e) {
            // Expected: implementation must throw when balance is insufficient
        }

        // Balances must be unchanged after a failed transfer
        assertEquals("Source balance must be unchanged after failed transfer",
                     10_00L, poor.getBalanceCents());
        assertEquals("Destination balance must be unchanged after failed transfer",
                     500_00L, rich.getBalanceCents());
        assertEquals("No audit entry should exist for a failed transfer",
                     0, logger.getLogCount());
    }

    // -----------------------------------------------------------------------
    // Deadlock test (exercises TransferService lock ordering bug)
    // -----------------------------------------------------------------------

    @Test(timeout = 6000)
    public void testBidirectionalTransfersCompleteWithoutDeadlock() throws InterruptedException {
        AuditLogger logger = new AuditLogger();
        TransferService service = new TransferService(logger);

        Account accountA = new Account("ACCT-A", "Treasury A", 100_000_00L);
        Account accountB = new Account("ACCT-B", "Treasury B", 100_000_00L);

        int transfers = 200;
        CountDownLatch startGate = new CountDownLatch(1);
        CountDownLatch doneLatch  = new CountDownLatch(2);

        // Thread 1: A → B repeatedly
        Thread t1 = new Thread(() -> {
            try {
                startGate.await();
                for (int i = 0; i < transfers; i++) {
                    service.transfer(accountA, accountB, 1_00L);
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } finally {
                doneLatch.countDown();
            }
        }, "TransferThread-A-to-B");

        // Thread 2: B → A repeatedly (opposite direction — classic deadlock scenario)
        Thread t2 = new Thread(() -> {
            try {
                startGate.await();
                for (int i = 0; i < transfers; i++) {
                    service.transfer(accountB, accountA, 1_00L);
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } finally {
                doneLatch.countDown();
            }
        }, "TransferThread-B-to-A");

        t1.start();
        t2.start();
        startGate.countDown();

        boolean finished = doneLatch.await(5, TimeUnit.SECONDS);
        t1.interrupt();
        t2.interrupt();

        assertTrue(
            "DEADLOCK DETECTED: bidirectional transfers did not complete within 5 seconds. " +
            "TransferService.transfer() acquires locks in argument order. Fix: always acquire " +
            "account locks in a canonical order (e.g., sorted by accountId) to prevent deadlock.",
            finished
        );

        // Money must be conserved (zero-sum: each thread does equal opposite transfers)
        long totalBefore = 200_000_00L;
        long totalAfter  = accountA.getBalanceCents() + accountB.getBalanceCents();
        assertEquals("Total money must be conserved across both accounts", totalBefore, totalAfter);
    }

    // -----------------------------------------------------------------------
    // ConcurrentModificationException test (exercises AuditLogger bug)
    // -----------------------------------------------------------------------

    @Test
    public void testProcessPendingAlertsDoesNotThrow() {
        AuditLogger logger = new AuditLogger();
        logger.log("TRANSFER from=ACC-1 to=ACC-2 amount=500 cents");
        logger.log("ALERT: unusually large transfer detected (amount=999999)");
        logger.log("TRANSFER from=ACC-3 to=ACC-4 amount=100 cents");
        logger.log("ALERT: transfer from sanctioned entity ACC-99");
        logger.log("TRANSFER from=ACC-5 to=ACC-6 amount=200 cents");

        try {
            logger.processPendingAlerts();
        } catch (java.util.ConcurrentModificationException e) {
            fail(
                "AuditLogger.processPendingAlerts() threw ConcurrentModificationException. " +
                "The method removes entries from 'entries' while iterating over it with a for-each loop. " +
                "Fix: use entries.removeIf(e -> e.startsWith(\"ALERT\")), " +
                "or collect entries to remove first, then remove them after the loop."
            );
        }

        // After processing, only non-ALERT entries should remain
        assertEquals(
            "Only non-ALERT entries should remain after processPendingAlerts()",
            3, logger.getLogCount()
        );
        for (String entry : logger.getEntries()) {
            assertFalse("No ALERT entry should remain after processing", entry.startsWith("ALERT"));
        }
    }
}
