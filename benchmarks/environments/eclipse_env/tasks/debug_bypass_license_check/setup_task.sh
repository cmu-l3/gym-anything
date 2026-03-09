#!/bin/bash
echo "=== Setting up debug_bypass_license_check task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
PROJECT_ROOT="/home/ga/Downloads/EnterpriseServer"
SRC_DIR="$PROJECT_ROOT/src/main/java/com/enterprise/server"

# Clean up previous runs
rm -rf "$PROJECT_ROOT" 2>/dev/null || true
rm -rf "/home/ga/eclipse-workspace/EnterpriseServer" 2>/dev/null || true

# Create Project Structure
mkdir -p "$SRC_DIR"

# 1. Create pom.xml
cat > "$PROJECT_ROOT/pom.xml" << 'EOF_POM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.enterprise</groupId>
  <artifactId>EnterpriseServer</artifactId>
  <packaging>jar</packaging>
  <version>4.2-SNAPSHOT</version>
  <name>EnterpriseServer</name>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
</project>
EOF_POM

# 2. Create ServerBootstrapper.java (Main Class)
cat > "$SRC_DIR/ServerBootstrapper.java" << 'EOF_MAIN'
package com.enterprise.server;

import java.io.FileWriter;
import java.io.IOException;
import java.time.LocalDateTime;

public class ServerBootstrapper {
    public static void main(String[] args) {
        System.out.println("--------------------------------------------------");
        System.out.println("   Enterprise Server Bootstrapper v4.2");
        System.out.println("--------------------------------------------------");
        System.out.println("Initializing core services...");
        
        LicenseManager lm = new LicenseManager();
        System.out.println("Verifying license with remote server...");
        
        if (lm.checkLicense()) {
            System.out.println("License validated successfully.");
            startServer();
        } else {
            System.err.println("CRITICAL ERROR: License validation failed.");
            System.err.println("Server startup aborted. Please contact support.");
            System.exit(1);
        }
    }

    private static void startServer() {
        System.out.println("Starting application context...");
        try {
            // Simulate startup time
            Thread.sleep(1000);
            System.out.println("Server Started Successfully on port 8080");
            
            // Create success artifact
            try (FileWriter fw = new FileWriter("startup_success.log")) {
                fw.write("SUCCESS_TOKEN_BYPASS_COMPLETE\n");
                fw.write("Timestamp: " + LocalDateTime.now());
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
EOF_MAIN

# 3. Create LicenseManager.java (The file to debug)
cat > "$SRC_DIR/LicenseManager.java" << 'EOF_LM'
package com.enterprise.server;

import java.util.Random;

public class LicenseManager {
    
    public boolean checkLicense() {
        // This variable is what the agent needs to modify at runtime via debugger
        boolean isLicensed = false; 
        
        try {
            // Simulate network latency for license server check
            System.out.println("Connecting to license.enterprise-internal.net...");
            Thread.sleep(2000);
            
            // Simulation of a server that is unreachable or returns false
            // In a real scenario, this might parse a response. 
            // Here it just stays false.
            
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        // Logic breakpoint usually goes here
        if (isLicensed) {
            return true;
        } else {
            return false;
        }
    }
}
EOF_LM

# 4. Create ConfigurationLoader.java (Filler)
cat > "$SRC_DIR/ConfigurationLoader.java" << 'EOF_CFG'
package com.enterprise.server;

public class ConfigurationLoader {
    public void load() {
        System.out.println("Loading configuration from /etc/enterprise/server.conf");
    }
}
EOF_CFG

# Set permissions
chown -R ga:ga "$PROJECT_ROOT"

# Make LicenseManager read-only to discourage editing (though agent can chmod)
chmod 444 "$SRC_DIR/LicenseManager.java"

# Calculate and store the initial hash of LicenseManager.java for integrity checking
md5sum "$SRC_DIR/LicenseManager.java" | awk '{print $1}' > /tmp/license_manager_original_hash.txt
chown ga:ga /tmp/license_manager_original_hash.txt

# Ensure Eclipse is ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
dismiss_dialogs 3
close_welcome_tab

# Final stabilization
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Project created at: $PROJECT_ROOT"
echo "Original LicenseManager hash saved."