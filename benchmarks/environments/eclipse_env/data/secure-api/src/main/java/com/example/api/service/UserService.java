package com.example.api.service;

import com.example.api.model.User;
import com.example.api.repository.UserRepository;

import java.sql.SQLException;
import java.util.List;
import java.util.Optional;

/**
 * Business logic layer for user management operations.
 */
public class UserService {

    private final UserRepository userRepository;

    public UserService(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    public Optional<User> getUser(String username) throws SQLException {
        if (username == null || username.isBlank()) {
            throw new IllegalArgumentException("Username must not be blank");
        }
        return userRepository.findByUsername(username);
    }

    public List<User> getUsersByDomain(String domain) throws SQLException {
        if (domain == null || domain.isBlank()) {
            throw new IllegalArgumentException("Domain must not be blank");
        }
        return userRepository.findByEmailDomain(domain);
    }

    public List<User> getUsersByRole(String role) throws SQLException {
        if (role == null || role.isBlank()) {
            throw new IllegalArgumentException("Role must not be blank");
        }
        return userRepository.findByRole(role);
    }

    public int createUser(String username, String email, String role) throws SQLException {
        User user = new User(0, username, email, role);
        return userRepository.save(user);
    }
}
