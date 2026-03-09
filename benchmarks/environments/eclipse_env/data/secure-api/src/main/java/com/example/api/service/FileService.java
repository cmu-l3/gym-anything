package com.example.api.service;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Service for reading and managing user-specific files on disk.
 * Files are stored under a configurable base directory.
 */
public class FileService {

    private final String baseDirectory;

    public FileService(String baseDirectory) {
        this.baseDirectory = baseDirectory;
    }

    /**
     * Read the contents of a user file.
     * NOTE: File path built by direct string concatenation — allows path traversal.
     *
     * @param userId   ID of the requesting user
     * @param filename Filename provided by user (potentially malicious)
     */
    public String readUserFile(int userId, String filename) throws IOException {
        String filePath = baseDirectory + File.separator + userId + File.separator + filename;
        File file = new File(filePath);
        StringBuilder sb = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line).append("\n");
            }
        }
        return sb.toString();
    }

    /**
     * Delete a user file.
     * NOTE: No canonical path check — path traversal possible via "../../../etc/passwd".
     *
     * @param userId   ID of the requesting user
     * @param filename Filename provided by user
     */
    public boolean deleteUserFile(int userId, String filename) throws IOException {
        String filePath = baseDirectory + File.separator + userId + File.separator + filename;
        File file = new File(filePath);
        return file.delete();
    }

    /**
     * Return the resolved file path for a given user and filename.
     * NOTE: Path constructed without validation against base directory.
     */
    public String getFilePath(int userId, String filename) {
        return baseDirectory + File.separator + userId + File.separator + filename;
    }

    public String getBaseDirectory() {
        return baseDirectory;
    }
}
