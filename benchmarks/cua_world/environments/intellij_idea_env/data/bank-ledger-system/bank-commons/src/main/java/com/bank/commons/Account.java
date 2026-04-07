package com.bank.commons;

/**
 * Represents a bank account with a unique identifier, holder name, and status.
 * Account status determines what operations are permitted.
 */
public class Account {

    public enum Status { ACTIVE, FROZEN, CLOSED }

    private final String accountId;
    private final String holderName;
    private Status status;

    public Account(String accountId, String holderName) {
        if (accountId == null || accountId.isEmpty()) {
            throw new IllegalArgumentException("Account ID cannot be null or empty");
        }
        if (holderName == null || holderName.isEmpty()) {
            throw new IllegalArgumentException("Holder name cannot be null or empty");
        }
        this.accountId = accountId;
        this.holderName = holderName;
        this.status = Status.ACTIVE;
    }

    public String getAccountId() { return accountId; }
    public String getHolderName() { return holderName; }
    public Status getStatus() { return status; }

    public void setStatus(Status status) {
        this.status = status;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Account account = (Account) o;
        return accountId.equals(account.accountId);
    }

    @Override
    public int hashCode() {
        return accountId.hashCode();
    }

    @Override
    public String toString() {
        return String.format("Account{id='%s', holder='%s', status=%s}",
                accountId, holderName, status);
    }
}
