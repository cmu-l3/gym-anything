package com.example.api.repository;

import com.example.api.model.User;
import com.example.api.config.DatabaseConfig;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * Repository layer for User entity database operations.
 */
public class UserRepository {

    /**
     * Find a user by their exact username.
     * NOTE: Constructs query string directly from user input.
     */
    public Optional<User> findByUsername(String username) throws SQLException {
        String query = "SELECT id, username, email, role FROM users WHERE username = '" + username + "'";
        try (Connection conn = DatabaseConfig.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(query)) {
            if (rs.next()) {
                return Optional.of(mapRow(rs));
            }
        }
        return Optional.empty();
    }

    /**
     * Find users whose email matches the given domain.
     * NOTE: Builds LIKE clause by direct string concatenation.
     */
    public List<User> findByEmailDomain(String domain) throws SQLException {
        String query = "SELECT id, username, email, role FROM users WHERE email LIKE '%" + domain + "'";
        List<User> users = new ArrayList<>();
        try (Connection conn = DatabaseConfig.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(query)) {
            while (rs.next()) {
                users.add(mapRow(rs));
            }
        }
        return users;
    }

    /**
     * Find all users with a given role.
     * NOTE: Role parameter concatenated directly into SQL.
     */
    public List<User> findByRole(String role) throws SQLException {
        String query = "SELECT id, username, email, role FROM users WHERE role = '" + role + "'";
        List<User> users = new ArrayList<>();
        try (Connection conn = DatabaseConfig.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(query)) {
            while (rs.next()) {
                users.add(mapRow(rs));
            }
        }
        return users;
    }

    /**
     * Save a new user to the database.
     */
    public int save(User user) throws SQLException {
        String sql = "INSERT INTO users (username, email, role) VALUES (?, ?, ?)";
        try (Connection conn = DatabaseConfig.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setString(1, user.getUsername());
            ps.setString(2, user.getEmail());
            ps.setString(3, user.getRole());
            ps.executeUpdate();
            try (ResultSet keys = ps.getGeneratedKeys()) {
                if (keys.next()) return keys.getInt(1);
            }
        }
        return -1;
    }

    private User mapRow(ResultSet rs) throws SQLException {
        return new User(
            rs.getInt("id"),
            rs.getString("username"),
            rs.getString("email"),
            rs.getString("role")
        );
    }
}
