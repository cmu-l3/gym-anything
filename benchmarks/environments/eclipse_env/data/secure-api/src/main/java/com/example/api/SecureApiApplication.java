package com.example.api;

import com.example.api.config.DatabaseConfig;
import com.example.api.repository.UserRepository;
import com.example.api.service.FileService;
import com.example.api.service.UserService;

import java.sql.Connection;
import java.sql.Statement;

/**
 * Main application entry point for the Secure API.
 */
public class SecureApiApplication {

    public static void main(String[] args) throws Exception {
        System.out.println("Secure API Application starting...");

        // Initialize schema
        try (Connection conn = DatabaseConfig.getConnection();
             Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE TABLE IF NOT EXISTS users (" +
                "id INT AUTO_INCREMENT PRIMARY KEY, " +
                "username VARCHAR(50) NOT NULL, " +
                "email VARCHAR(100) NOT NULL, " +
                "role VARCHAR(20) NOT NULL)");
        }

        UserRepository userRepo = new UserRepository();
        UserService userService = new UserService(userRepo);
        FileService fileService = new FileService("/var/app/userfiles");

        System.out.println("Services initialized. Ready.");
    }
}
