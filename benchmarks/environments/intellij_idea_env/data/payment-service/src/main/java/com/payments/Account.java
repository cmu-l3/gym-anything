package com.payments;

/**
 * Represents a bank account with a balance. Used in concurrent payment workflows
 * where multiple threads may simultaneously initiate deposits and withdrawals.
 *
 * <p>This class is shared between multiple service layers and must correctly
 * enforce balance invariants even under concurrent access.
 */
public class Account {

    private final String accountId;
    private final String ownerName;
    private long balanceCents;  // balance stored in cents to avoid floating-point issues

    public Account(String accountId, String ownerName, long initialBalanceCents) {
        if (initialBalanceCents < 0) {
            throw new IllegalArgumentException("Initial balance cannot be negative");
        }
        this.accountId = accountId;
        this.ownerName = ownerName;
        this.balanceCents = initialBalanceCents;
    }

    public String getAccountId() {
        return accountId;
    }

    public String getOwnerName() {
        return ownerName;
    }

    public long getBalanceCents() {
        return balanceCents;
    }

    /**
     * Deposits the specified amount (in cents) into this account.
     *
     * @param amountCents amount to deposit; must be positive
     * @throws IllegalArgumentException if amount is not positive
     */
    public synchronized void deposit(long amountCents) {
        if (amountCents <= 0) {
            throw new IllegalArgumentException("Deposit amount must be positive, received: " + amountCents);
        }
        balanceCents += amountCents;
    }

    /**
     * Withdraws the specified amount (in cents) from this account.
     *
     * <p>BUG: This method does not verify that sufficient funds exist before
     * subtracting. An overdraft can silently result in a negative balance,
     * violating the account invariant. The caller expects an exception when
     * funds are insufficient.
     *
     * @param amountCents amount to withdraw; must be positive
     * @throws IllegalArgumentException if amount is not positive
     */
    public synchronized void withdraw(long amountCents) {
        if (amountCents <= 0) {
            throw new IllegalArgumentException("Withdrawal amount must be positive, received: " + amountCents);
        }
        // BUG: missing check: if (balanceCents < amountCents) throw new InsufficientFundsException(...)
        balanceCents -= amountCents;
    }

    @Override
    public String toString() {
        return String.format("Account{id='%s', owner='%s', balance=%d cents}", accountId, ownerName, balanceCents);
    }
}
