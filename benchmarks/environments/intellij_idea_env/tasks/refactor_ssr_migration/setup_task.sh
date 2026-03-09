#!/bin/bash
set -e
echo "=== Setting up Refactor SSR Migration Task ==="

source /workspace/scripts/task_utils.sh

# Define project paths
PROJECT_NAME="legacy-logging-system"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"

# Clean up any previous run
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/logging/service"

echo "Generating project files..."

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POM'
<project xmlns="http://maven.apache.org/POM/4.0.0" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.logging</groupId>
    <artifactId>legacy-logging-system</artifactId>
    <version>1.0-SNAPSHOT</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
</project>
POM

# 2. Create LogLevel Enum
cat > "$PROJECT_DIR/src/main/java/com/logging/LogLevel.java" << 'JAVA'
package com.logging;

public enum LogLevel {
    INFO, DEBUG, ERROR, WARN, TRACE
}
JAVA

# 3. Create LegacyLogger (The Old API)
cat > "$PROJECT_DIR/src/main/java/com/logging/LegacyLogger.java" << 'JAVA'
package com.logging;

public class LegacyLogger {
    public static void log(String message, LogLevel level, long timestamp) {
        System.out.println("[" + level + "] " + timestamp + ": " + message);
    }
}
JAVA

# 4. Create FluentLogger (The New API)
cat > "$PROJECT_DIR/src/main/java/com/logging/FluentLogger.java" << 'JAVA'
package com.logging;

public class FluentLogger {
    private LogLevel level;
    private long timestamp;

    private FluentLogger(LogLevel level) {
        this.level = level;
    }

    public static FluentLogger at(LogLevel level) {
        return new FluentLogger(level);
    }

    public FluentLogger withTime(long timestamp) {
        this.timestamp = timestamp;
        return this;
    }

    public void log(String message) {
        System.out.println("{" + timestamp + "} [" + level + "] " + message);
    }
}
JAVA

# 5. Create LogService (The Target for Refactoring)
# We generate a file with mixed usage patterns (literals, variables, method calls)
# to make simple Regex replacement difficult and justify SSR.
cat > "$PROJECT_DIR/src/main/java/com/logging/service/LogService.java" << 'JAVA'
package com.logging.service;

import com.logging.LegacyLogger;
import com.logging.FluentLogger;
import com.logging.LogLevel;
import java.time.Instant;

public class LogService {

    public void processTransaction(String user, int amount) {
        // Simple usage
        LegacyLogger.log("Transaction started", LogLevel.INFO, System.currentTimeMillis());

        try {
            validate(amount);
            // Variable usage
            long now = System.currentTimeMillis();
            LegacyLogger.log("Validation successful", LogLevel.DEBUG, now);
        } catch (Exception e) {
            // Complex string concatenation
            LegacyLogger.log("Error processing: " + e.getMessage(), LogLevel.ERROR, Instant.now().toEpochMilli());
        }

        // Literal timestamp
        LegacyLogger.log("Audit checkpoint", LogLevel.TRACE, 1678892000L);
    }

    private void validate(int amount) {
        if (amount < 0) {
            LegacyLogger.log("Negative amount detected", LogLevel.WARN, System.currentTimeMillis());
            throw new IllegalArgumentException("Invalid amount");
        }
    }

    public void bulkOperations() {
JAVA

# Generate 45 additional lines to make manual editing tedious
for i in {1..45}; do
    # Vary the timestamp argument
    TIME_ARG="System.currentTimeMillis()"
    [ $((i % 3)) -eq 0 ] && TIME_ARG="Instant.now().toEpochMilli()"
    [ $((i % 5)) -eq 0 ] && TIME_ARG="123456789${i}L"
    
    # Vary the message argument
    MSG_ARG="\"Operation $i processed\""
    [ $((i % 2)) -eq 0 ] && MSG_ARG="\"User \" + \"user$i\" + \" active\""
    
    # Vary the level argument
    LEVEL_ARG="LogLevel.INFO"
    [ $((i % 4)) -eq 0 ] && LEVEL_ARG="LogLevel.DEBUG"
    
    echo "        LegacyLogger.log($MSG_ARG, $LEVEL_ARG, $TIME_ARG);" >> "$PROJECT_DIR/src/main/java/com/logging/service/LogService.java"
done

echo "    }" >> "$PROJECT_DIR/src/main/java/com/logging/service/LogService.java"
echo "}" >> "$PROJECT_DIR/src/main/java/com/logging/service/LogService.java"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record initial state info for verification
date +%s > /tmp/task_start_time.txt
md5sum "$PROJECT_DIR/src/main/java/com/logging/service/LogService.java" > /tmp/initial_file_hash.txt

# Open the project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "legacy-logging-system" 120

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="