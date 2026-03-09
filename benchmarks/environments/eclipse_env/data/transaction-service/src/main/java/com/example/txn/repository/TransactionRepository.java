package com.example.txn.repository;

import com.example.txn.model.Transaction;

import java.util.List;
import java.util.Optional;

public interface TransactionRepository {
    Transaction save(Transaction transaction);
    Optional<Transaction> findById(String id);
    List<Transaction> findByAccountId(String accountId);
    List<Transaction> findAll();
    void deleteById(String id);
}
