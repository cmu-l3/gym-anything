#!/bin/bash
set -e
echo "=== Setting up Navigate Legacy Codebase task ==="

source /workspace/scripts/task_utils.sh

# Define paths
PROJECT_DIR="/home/ga/IdeaProjects/LegacyAuthSystem"
mkdir -p "$PROJECT_DIR/src/main/java/com/enterprise/auth/api"
mkdir -p "$PROJECT_DIR/src/main/java/com/enterprise/auth/impl"
mkdir -p "$PROJECT_DIR/src/main/java/com/enterprise/auth/config"
mkdir -p "$PROJECT_DIR/src/main/java/com/enterprise/auth/base"
mkdir -p "$PROJECT_DIR/src/main/java/com/enterprise/auth/service"

# 1. POM
cat > "$PROJECT_DIR/pom.xml" << 'POM'
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.enterprise</groupId>
    <artifactId>legacy-auth-system</artifactId>
    <version>1.0.0</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
</project>
POM

# 2. Interface
cat > "$PROJECT_DIR/src/main/java/com/enterprise/auth/api/SecurityProvider.java" << 'JAVA'
package com.enterprise.auth.api;

public interface SecurityProvider {
    void initialize();
    String getFallbackKey();
    boolean validateToken(String token);
}
JAVA

# 3. Config Registry (The Treasure Map)
cat > "$PROJECT_DIR/src/main/java/com/enterprise/auth/config/ConfigurationRegistry.java" << 'JAVA'
package com.enterprise.auth.config;

public class ConfigurationRegistry {
    public static final String REGION_PREFIX = "US-EAST";
    // Legacy fallback parameters
    public static final String PROTOCOL_V1 = "AUTH-V1";
    public static final String PROTOCOL_V2 = "AUTH-V2";
    
    public static final class Internal {
        public static final String SEGMENT_A = "KEY-742";
        public static final String SEGMENT_B = "BETA";
    }
}
JAVA

# 4. Abstract Base
cat > "$PROJECT_DIR/src/main/java/com/enterprise/auth/base/AbstractBaseProvider.java" << 'JAVA'
package com.enterprise.auth.base;

import com.enterprise.auth.api.SecurityProvider;
import com.enterprise.auth.config.ConfigurationRegistry;

public abstract class AbstractBaseProvider implements SecurityProvider {
    
    protected String assembleKey(String specificPart) {
        // The master format is: PROTOCOL-REGION-SPECIFIC-TIMESTAMP
        // But for fallback, we use a static generation
        return ConfigurationRegistry.PROTOCOL_V2 + "-" + 
               ConfigurationRegistry.REGION_PREFIX + "-" + 
               specificPart;
    }
}
JAVA

# 5. Mock Impl (Decoy)
cat > "$PROJECT_DIR/src/main/java/com/enterprise/auth/impl/MockSecurityProvider.java" << 'JAVA'
package com.enterprise.auth.impl;

import com.enterprise.auth.base.AbstractBaseProvider;

public class MockSecurityProvider extends AbstractBaseProvider {
    @Override
    public void initialize() {
        System.out.println("Mock init");
    }

    @Override
    public String getFallbackKey() {
        return "TEST-KEY-000000"; // Decoy value
    }

    @Override
    public boolean validateToken(String token) {
        return true;
    }
}
JAVA

# 6. Production Impl (Target)
cat > "$PROJECT_DIR/src/main/java/com/enterprise/auth/impl/ProductionSecurityProvider.java" << 'JAVA'
package com.enterprise.auth.impl;

import com.enterprise.auth.base.AbstractBaseProvider;
import com.enterprise.auth.config.ConfigurationRegistry;

/**
 * Primary security provider for the Mainframe environment.
 * DO NOT INSTANTIATE LOCALLY - REQUIRES HARDWARE TOKEN.
 */
public class ProductionSecurityProvider extends AbstractBaseProvider {
    
    @Override
    public void initialize() {
        // Simulating crash if run locally
        throw new RuntimeException("MainframeConnectionException: connection timed out to 10.0.0.1");
    }

    @Override
    public String getFallbackKey() {
        // Constructing the complex key
        String core = ConfigurationRegistry.Internal.SEGMENT_A;
        String variant = ConfigurationRegistry.Internal.SEGMENT_B;
        return assembleKey(core + "-" + variant);
    }

    @Override
    public boolean validateToken(String token) {
        throw new RuntimeException("Mainframe unreachable");
    }
}
JAVA

# 7. Service (Entry Point)
cat > "$PROJECT_DIR/src/main/java/com/enterprise/auth/service/AuthenticationManager.java" << 'JAVA'
package com.enterprise.auth.service;

import com.enterprise.auth.api.SecurityProvider;
import com.enterprise.auth.impl.ProductionSecurityProvider;

public class AuthenticationManager {
    
    private final SecurityProvider provider;

    public AuthenticationManager() {
        // In production, this is injected. Here we default to Production.
        this.provider = new ProductionSecurityProvider();
    }

    public void start() {
        provider.initialize();
        System.out.println("Manager started");
    }
    
    public String getEmergencyKey() {
        return provider.getFallbackKey();
    }
    
    public static void main(String[] args) {
        new AuthenticationManager().start();
    }
}
JAVA

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# Calculate initial checksums of source files (to detect modification)
find "$PROJECT_DIR/src/main/java" -name "*.java" -type f -exec md5sum {} \; | sort > /tmp/initial_source_checksums.txt

# Launch IntelliJ with project
setup_intellij_project "$PROJECT_DIR" "LegacyAuthSystem"

# Take initial screenshot
take_screenshot /tmp/task_start.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="