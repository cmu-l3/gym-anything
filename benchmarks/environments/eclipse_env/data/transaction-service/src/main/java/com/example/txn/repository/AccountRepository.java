package com.example.txn.repository;

import com.example.txn.model.Account;

import java.util.List;
import java.util.Optional;

public interface AccountRepository {
    Account save(Account account);
    Optional<Account> findById(String id);
    Optional<Account> findByAccountNumber(String accountNumber);
    List<Account> findByOwnerId(String ownerId);
    List<Account> findAll();
}
