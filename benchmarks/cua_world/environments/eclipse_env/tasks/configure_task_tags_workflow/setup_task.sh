#!/bin/bash
set -e
echo "=== Setting up Configure Task Tags Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/LegacyAuth"
SRC_DIR="$PROJECT_DIR/src/main/java/com/legacy/auth"

# Clean previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true

# Create project structure
mkdir -p "$SRC_DIR"
mkdir -p "$PROJECT_DIR/.settings"

# 1. Create .project file
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>LegacyAuth</name>
	<comment></comment>
	<projects>
	</projects>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.jdt.core.javabuilder</name>
			<arguments>
			</arguments>
		</buildCommand>
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
	</natures>
</projectDescription>
EOF

# 2. Create .classpath file
cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src/main/java"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/java-17-openjdk-amd64"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOF

# 3. Create UserDAO.java with the SECURITY tag and backdoor
# This is the file the agent must modify
cat > "$SRC_DIR/UserDAO.java" << 'EOF'
package com.legacy.auth;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;

/**
 * Data Access Object for User authentication.
 */
public class UserDAO {

    public boolean authenticate(String username, String password) {
        if (username == null || password == null) {
            return false;
        }

        // SECURITY: Hardcoded backdoor for testing - REMOVE BEFORE DEPLOY
        // This allows developers to bypass auth in dev environment
        if ("superuser".equals(username) && "pass123".equals(password)) {
            System.out.println("WARNING: Superuser bypass used");
            return true;
        }

        return checkCredentialsInDb(username, password);
    }

    private boolean checkCredentialsInDb(String username, String password) {
        // Simulation of DB check
        return "admin".equals(username) && "securePass".equals(password);
    }
    
    public void updateUser(String username, String email) {
        // TODO: Implement update logic
        throw new UnsupportedOperationException("Not implemented");
    }
}
EOF

# 4. Create SessionManager.java with PERF tag
cat > "$SRC_DIR/SessionManager.java" << 'EOF'
package com.legacy.auth;

import java.util.HashMap;
import java.util.Map;
import java.security.SecureRandom;

public class SessionManager {
    
    private Map<String, String> activeSessions = new HashMap<>();
    
    public String createSession(String username) {
        // PERF: SecureRandom is slow, consider caching the instance or using a pool
        SecureRandom random = new SecureRandom();
        byte[] bytes = new byte[24];
        random.nextBytes(bytes);
        
        String token = bytesToHex(bytes);
        activeSessions.put(token, username);
        return token;
    }
    
    private String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
}
EOF

# 5. Create AuthUtils.java (filler)
cat > "$SRC_DIR/AuthUtils.java" << 'EOF'
package com.legacy.auth;

public class AuthUtils {
    // FIXME: This constant should be in a config file
    public static final int MAX_RETRIES = 3;
    
    public static boolean isValidEmail(String email) {
        return email != null && email.contains("@");
    }
}
EOF

# Set permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Wait for Eclipse and ensure it's ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Focus and maximize Eclipse window
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "LegacyAuth project created at $PROJECT_DIR"