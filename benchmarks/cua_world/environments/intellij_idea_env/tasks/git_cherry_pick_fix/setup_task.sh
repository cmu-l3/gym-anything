#!/bin/bash
set -e
echo "=== Setting up task: git_cherry_pick_fix ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Define paths
PROJECT_NAME="auth-service"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"

# Clean up any previous run
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# 2. Prepare Git Repo and History (Running as 'ga' user)
# We construct a scenario where 'feature/v2-upgrade' has [WIP, FIX, WIP]
su - ga -c "
    # Configure Git
    git config --global user.email 'dev@auth-service.com'
    git config --global user.name 'Dev User'
    git config --global init.defaultBranch main

    # Initialize Repo
    mkdir -p '$PROJECT_DIR/src/main/java/com/example/auth'
    cd '$PROJECT_DIR'
    git init

    # --- Initial Commit on MAIN ---
    # Create pom.xml
    cat > pom.xml << 'EOF'
<project xmlns=\"http://maven.apache.org/POM/4.0.0\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"
  xsi:schemaLocation=\"http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd\">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>auth-service</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
</project>
EOF

    # Create Vulnerable AuthUtils.java
    cat > src/main/java/com/example/auth/AuthUtils.java << 'EOF'
package com.example.auth;

import java.util.Arrays;
import java.nio.charset.StandardCharsets;

public class AuthUtils {
    
    /**
     * Verifies a password hash against the stored hash.
     * WARNING: This implementation is vulnerable to timing attacks.
     */
    public static boolean verifyHash(String input, String stored) {
        if (input == null || stored == null) return false;
        
        byte[] inputBytes = input.getBytes(StandardCharsets.UTF_8);
        byte[] storedBytes = stored.getBytes(StandardCharsets.UTF_8);
        
        // VULNERABLE: Arrays.equals returns as soon as a byte mismatch is found
        return Arrays.equals(inputBytes, storedBytes);
    }
}
EOF

    git add .
    git commit -m 'Initial commit: Basic auth utilities'

    # --- Create Feature Branch ---
    git checkout -b feature/v2-upgrade

    # Commit 1: WIP (Work In Progress) - Unwanted on main
    # We append a TODO to the end of the file
    sed -i 's/}/    \/\/ TODO: Implement OAuth2 support\n}/' src/main/java/com/example/auth/AuthUtils.java
    git add src/main/java/com/example/auth/AuthUtils.java
    git commit -m 'WIP: Start adding OAuth2 stubs'

    # Commit 2: THE FIX (Target for Cherry-Pick)
    # Rewrite AuthUtils.java to use MessageDigest.isEqual, KEEPING the WIP comment from previous commit
    # This simulates that the fix was done ON TOP of the WIP work
    cat > src/main/java/com/example/auth/AuthUtils.java << 'EOF'
package com.example.auth;

import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

public class AuthUtils {
    
    /**
     * Verifies a password hash against the stored hash.
     * Secure implementation using constant-time comparison.
     */
    public static boolean verifyHash(String input, String stored) {
        if (input == null || stored == null) return false;
        
        byte[] inputBytes = input.getBytes(StandardCharsets.UTF_8);
        byte[] storedBytes = stored.getBytes(StandardCharsets.UTF_8);
        
        // SECURE: MessageDigest.isEqual compares all bytes regardless of match
        return MessageDigest.isEqual(inputBytes, storedBytes);
    }
    
    // TODO: Implement OAuth2 support
}
EOF
    git add src/main/java/com/example/auth/AuthUtils.java
    git commit -m 'FIX: Use constant-time comparison to prevent timing attacks'

    # Commit 3: More WIP - Unwanted on main
    sed -i 's/}/    public void tempDebug() { System.out.println(\"Debug\"); }\n}/' src/main/java/com/example/auth/AuthUtils.java
    git add src/main/java/com/example/auth/AuthUtils.java
    git commit -m 'WIP: Add debug logging for v2 flow'

    # --- Return to Main ---
    # Main currently has the vulnerable code and NO WIP comments
    git checkout main
"

# 3. Open the project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "$PROJECT_NAME" 120

# 4. Open Git Tool Window (optional helper, but good for starting state)
# We can try to simulate Alt+9, but just having the project open is sufficient per requirements.
# The user needs to know to open it.

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="