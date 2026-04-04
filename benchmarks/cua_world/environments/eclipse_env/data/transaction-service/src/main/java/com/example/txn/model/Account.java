package com.example.txn.model;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public class Account {
    private String id;
    private String ownerId;
    private String accountNumber;
    private BigDecimal balance;
    private AccountType type;
    private boolean active;
    private LocalDateTime createdAt;

    public Account() {}

    public Account(String id, String ownerId, String accountNumber,
                   BigDecimal balance, AccountType type) {
        this.id = id;
        this.ownerId = ownerId;
        this.accountNumber = accountNumber;
        this.balance = balance;
        this.type = type;
        this.active = true;
        this.createdAt = LocalDateTime.now();
    }

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getOwnerId() { return ownerId; }
    public void setOwnerId(String ownerId) { this.ownerId = ownerId; }
    public String getAccountNumber() { return accountNumber; }
    public void setAccountNumber(String accountNumber) { this.accountNumber = accountNumber; }
    public BigDecimal getBalance() { return balance; }
    public void setBalance(BigDecimal balance) { this.balance = balance; }
    public AccountType getType() { return type; }
    public void setType(AccountType type) { this.type = type; }
    public boolean isActive() { return active; }
    public void setActive(boolean active) { this.active = active; }
    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }
}
