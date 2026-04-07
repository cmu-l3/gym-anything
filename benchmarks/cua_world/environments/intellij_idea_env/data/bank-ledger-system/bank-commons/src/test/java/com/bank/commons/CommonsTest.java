package com.bank.commons;

import org.junit.Test;
import static org.junit.Assert.*;

/**
 * Tests for shared commons models and utilities.
 */
public class CommonsTest {

    @Test
    public void testAccountCreation() {
        Account account = new Account("US10028374", "Alice Johnson");
        assertEquals("US10028374", account.getAccountId());
        assertEquals("Alice Johnson", account.getHolderName());
        assertEquals(Account.Status.ACTIVE, account.getStatus());
    }

    @Test
    public void testAccountStatusTransitions() {
        Account account = new Account("US10028374", "Alice Johnson");

        account.setStatus(Account.Status.FROZEN);
        assertEquals(Account.Status.FROZEN, account.getStatus());

        account.setStatus(Account.Status.CLOSED);
        assertEquals(Account.Status.CLOSED, account.getStatus());
    }

    @Test
    public void testMoneyUtilsRounding() {
        assertEquals(10.46, MoneyUtils.roundToTwoDecimals(10.456), 0.0001);
        assertEquals(-5.79, MoneyUtils.roundToTwoDecimals(-5.789), 0.0001);
        assertEquals(0.01, MoneyUtils.roundToTwoDecimals(0.005), 0.0001);

        assertTrue(MoneyUtils.isValidAmount(100.00));
        assertTrue(MoneyUtils.isValidAmount(0.01));
        assertFalse(MoneyUtils.isValidAmount(-1.00));
        assertFalse(MoneyUtils.isValidAmount(0));
        assertFalse(MoneyUtils.isValidAmount(Double.NaN));

        assertEquals("$1234.56", MoneyUtils.format(1234.56));
    }
}
