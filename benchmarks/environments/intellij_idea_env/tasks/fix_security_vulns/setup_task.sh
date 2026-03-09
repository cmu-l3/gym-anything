#!/bin/bash
set -e
echo "=== Setting up fix_security_vulns task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/security-audit"
PKG_DIR="$PROJECT_DIR/src/main/java/com/auditlib"

# Create project structure
mkdir -p "$PKG_DIR"
chown -R ga:ga "$PROJECT_DIR"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.auditlib</groupId>
  <artifactId>security-audit</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
</project>
POMEOF

# 2. Create SECURITY_AUDIT.md
cat > "$PROJECT_DIR/SECURITY_AUDIT.md" << 'MDEOF'
# Security Audit Report - Critical Findings

1. **SQL Injection** (`DatabaseHelper.java`)
   - Issue: User input is concatenated directly into SQL queries.
   - Fix: Use `PreparedStatement` with parameterized queries.

2. **Path Traversal** (`FileManager.java`)
   - Issue: Filenames are used without validation, allowing access to parent directories.
   - Fix: Validate that the canonical path starts with the base directory.

3. **Insecure Randomness** (`TokenGenerator.java`)
   - Issue: `java.util.Random` is predictable and unsuitable for security tokens.
   - Fix: Use `java.security.SecureRandom`.

4. **Hardcoded Credentials** (`ConfigLoader.java`)
   - Issue: Secrets are stored in plain text in source code.
   - Fix: Load from environment variables (e.g., `DB_PASSWORD`, `API_KEY`).

5. **XML External Entity (XXE)** (`XmlProcessor.java`)
   - Issue: XML parser processes external entities, allowing file exfiltration.
   - Fix: Disable DTDs and external entity processing in `DocumentBuilderFactory`.

6. **Weak Hashing** (`PasswordUtil.java`)
   - Issue: MD5 is broken and vulnerable to collision attacks.
   - Fix: Use a strong algorithm like PBKDF2, BCrypt, or Argon2 with salt.
MDEOF

# 3. Create Vulnerable Java Files

# VULNERABILITY 1: SQL Injection
cat > "$PKG_DIR/DatabaseHelper.java" << 'JAVAEOF'
package com.auditlib;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;

public class DatabaseHelper {
    public void searchUser(String username) {
        try {
            Connection conn = DriverManager.getConnection("jdbc:mysql://localhost:3306/db", "user", "pass");
            Statement stmt = conn.createStatement();
            // VULNERABLE: SQL Injection
            String query = "SELECT * FROM users WHERE username = '" + username + "'";
            ResultSet rs = stmt.executeQuery(query);
            while (rs.next()) {
                System.out.println("Found user: " + rs.getString("username"));
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
JAVAEOF

# VULNERABILITY 2: Path Traversal
cat > "$PKG_DIR/FileManager.java" << 'JAVAEOF'
package com.auditlib;

import java.io.File;
import java.io.FileReader;
import java.io.IOException;

public class FileManager {
    private final String baseDir = "/var/data/uploads";

    public String readFile(String filename) throws IOException {
        // VULNERABLE: Path Traversal (e.g., filename = "../../etc/passwd")
        File file = new File(baseDir, filename);
        
        StringBuilder content = new StringBuilder();
        try (FileReader reader = new FileReader(file)) {
            int c;
            while ((c = reader.read()) != -1) {
                content.append((char) c);
            }
        }
        return content.toString();
    }
}
JAVAEOF

# VULNERABILITY 3: Insecure Random
cat > "$PKG_DIR/TokenGenerator.java" << 'JAVAEOF'
package com.auditlib;

import java.util.Random;

public class TokenGenerator {
    public String generateSessionToken() {
        // VULNERABLE: Predictable PRNG
        Random random = new Random();
        byte[] bytes = new byte[16];
        random.nextBytes(bytes);
        return bytesToHex(bytes);
    }

    private String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
}
JAVAEOF

# VULNERABILITY 4: Hardcoded Credentials
cat > "$PKG_DIR/ConfigLoader.java" << 'JAVAEOF'
package com.auditlib;

public class ConfigLoader {
    public String getDatabasePassword() {
        // VULNERABLE: Hardcoded secret
        return "db_p@ssw0rd_2024!";
    }

    public String getApiKey() {
        // VULNERABLE: Hardcoded secret
        return "sk-api-9f8e7d6c5b4a3210";
    }
}
JAVAEOF

# VULNERABILITY 5: XXE
cat > "$PKG_DIR/XmlProcessor.java" << 'JAVAEOF'
package com.auditlib;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Document;
import java.io.InputStream;

public class XmlProcessor {
    public Document parseInvoice(InputStream xmlInput) throws Exception {
        // VULNERABLE: Default factory allows XXE
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        DocumentBuilder builder = factory.newDocumentBuilder();
        return builder.parse(xmlInput);
    }
}
JAVAEOF

# VULNERABILITY 6: Weak Hashing
cat > "$PKG_DIR/PasswordUtil.java" << 'JAVAEOF'
package com.auditlib;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

public class PasswordUtil {
    public String hashPassword(String password) {
        try {
            // VULNERABLE: MD5 is weak
            MessageDigest md = MessageDigest.getInstance("MD5");
            md.update(password.getBytes());
            byte[] digest = md.digest();
            return bytesToHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException(e);
        }
    }

    private String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
}
JAVAEOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record initial checksums for anti-gaming
echo "Recording initial state..."
find "$PKG_DIR" -name "*.java" -type f -exec sha256sum {} \; | sort > /tmp/initial_checksums.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Open IntelliJ
setup_intellij_project "$PROJECT_DIR" "security-audit" 180

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="