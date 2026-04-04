package com.example.api.repository;

import com.example.api.config.DatabaseConfig;
import com.example.api.model.User;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.sql.Connection;
import java.sql.Statement;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Basic smoke tests for UserRepository.
 * Note: These tests use the real database with the current (insecure) implementation.
 */
class UserRepositoryTest {

    private UserRepository repo;

    @BeforeEach
    void setUp() throws Exception {
        // Create schema and test data
        try (Connection conn = DatabaseConfig.getConnection();
             Statement stmt = conn.createStatement()) {
            stmt.execute("DROP TABLE IF EXISTS users");
            stmt.execute("CREATE TABLE users (" +
                "id INT AUTO_INCREMENT PRIMARY KEY, " +
                "username VARCHAR(50) NOT NULL, " +
                "email VARCHAR(100) NOT NULL, " +
                "role VARCHAR(20) NOT NULL)");
            stmt.execute("INSERT INTO users (username, email, role) VALUES " +
                "('alice', 'alice@example.com', 'admin'), " +
                "('bob', 'bob@example.com', 'user'), " +
                "('charlie', 'charlie@corp.net', 'user')");
        }
        repo = new UserRepository();
    }

    @Test
    void findByUsername_returnsUser() throws Exception {
        Optional<User> result = repo.findByUsername("alice");
        assertTrue(result.isPresent());
        assertEquals("alice", result.get().getUsername());
    }

    @Test
    void findByUsername_notFound_returnsEmpty() throws Exception {
        Optional<User> result = repo.findByUsername("nonexistent");
        assertFalse(result.isPresent());
    }
}
