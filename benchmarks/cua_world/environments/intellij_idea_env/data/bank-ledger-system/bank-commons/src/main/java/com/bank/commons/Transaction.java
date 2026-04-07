package com.bank.commons;

import java.time.LocalDateTime;

/**
 * Represents a financial transaction between accounts.
 * Transactions have a type (deposit, withdrawal, transfer) and a lifecycle status.
 */
public class Transaction {

    public enum Type { DEPOSIT, WITHDRAWAL, TRANSFER }
    public enum Status { PENDING, COMPLETED, FAILED, CANCELLED }

    private final String transactionId;
    private final String sourceAccountId;
    private final String destAccountId;
    private final double amount;
    private final Type type;
    private final LocalDateTime timestamp;
    private Status status;

    public Transaction(String transactionId, String sourceAccountId,
                       String destAccountId, double amount, Type type) {
        this.transactionId = transactionId;
        this.sourceAccountId = sourceAccountId;
        this.destAccountId = destAccountId;
        this.amount = amount;
        this.type = type;
        this.timestamp = LocalDateTime.now();
        this.status = Status.PENDING;
    }

    public String getTransactionId() { return transactionId; }
    public String getSourceAccountId() { return sourceAccountId; }
    public String getDestAccountId() { return destAccountId; }
    public double getAmount() { return amount; }
    public Type getType() { return type; }
    public LocalDateTime getTimestamp() { return timestamp; }
    public Status getStatus() { return status; }

    public void setStatus(Status status) { this.status = status; }

    @Override
    public String toString() {
        return String.format("Transaction{id='%s', from='%s', to='%s', amount=%.2f, type=%s, status=%s}",
                transactionId, sourceAccountId, destAccountId, amount, type, status);
    }
}
