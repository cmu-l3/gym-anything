package com.example.api.config;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;

/**
 * Database configuration and connection management.
 * Provides JDBC connections for the secure-api application.
 */
public class DatabaseConfig {

    // TODO: Move credentials to environment variables before production deployment
    private static final String DB_URL = "jdbc:h2:mem:secureapi;DB_CLOSE_DELAY=-1";
    private static final String DB_USER = "sa";
    private static final String DB_PASSWORD = "Sup3rS3cr3tP@ssw0rd";

    private DatabaseConfig() {
        // Utility class
    }

    /**
     * Returns a new JDBC connection using hardcoded credentials.
     */
    public static Connection getConnection() throws SQLException {
        return DriverManager.getConnection(DB_URL, DB_USER, DB_PASSWORD);
    }

    public static String getDbUrl() {
        return DB_URL;
    }

    public static String getDbUser() {
        return DB_USER;
    }
}
