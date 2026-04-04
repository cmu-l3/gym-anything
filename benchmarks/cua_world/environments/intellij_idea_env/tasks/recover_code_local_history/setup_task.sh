#!/bin/bash
set -e
echo "=== Setting up recover_code_local_history task ==="

source /workspace/scripts/task_utils.sh

# Configuration
PROJECT_DIR="/home/ga/IdeaProjects/fintech-core"
SRC_PKG_DIR="$PROJECT_DIR/src/main/java/com/fintech/core"
FILE_PATH="$SRC_PKG_DIR/TransactionValidator.java"

# 1. Create Project Structure
mkdir -p "$SRC_PKG_DIR"

# Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.fintech</groupId>
    <artifactId>fintech-core</artifactId>
    <version>1.0</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
</project>
EOF

# Create supporting classes (Transaction.java)
cat > "$SRC_PKG_DIR/Transaction.java" << 'EOF'
package com.fintech.core;
public class Transaction {
    private double amount;
    public Transaction(double amount) { this.amount = amount; }
    public double getAmount() { return amount; }
}
EOF

# Create supporting classes (UserTier.java)
cat > "$SRC_PKG_DIR/UserTier.java" << 'EOF'
package com.fintech.core;
public enum UserTier { STANDARD, GOLD, PLATINUM }
EOF

# 2. Create the "Good" File (The one to be recovered)
# This file contains the "secret" values the verifier looks for.
cat > "$FILE_PATH" << 'EOF'
package com.fintech.core;

/**
 * Validates financial transactions against tier limits.
 */
public class TransactionValidator {

    private static final double STANDARD_LIMIT = 2500.00;
    private static final double GOLD_LIMIT = 15000.00;
    private static final double PLATINUM_LIMIT = 50000.00;
    
    private static final String ERR_LIMIT_EXCEEDED = "ERR_099: Transaction exceeds daily tier limit";
    private static final String ERR_INVALID_STATE = "ERR_102: Account suspended or frozen";

    public boolean validate(Transaction tx, UserTier tier) {
        if (tx == null) return false;
        
        if (tx.getAmount() <= 0) {
            System.out.println("Error: Negative amount");
            return false;
        }

        double limit = STANDARD_LIMIT;
        switch (tier) {
            case GOLD:
                limit = GOLD_LIMIT;
                break;
            case PLATINUM:
                limit = PLATINUM_LIMIT;
                break;
            case STANDARD:
            default:
                limit = STANDARD_LIMIT;
                break;
        }

        if (tx.getAmount() > limit) {
            System.out.println(ERR_LIMIT_EXCEEDED + " [" + limit + "]");
            return false;
        }

        return true;
    }
}
EOF

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# 3. Launch IntelliJ with the project to establish Local History
echo "Launching IntelliJ to establish history baseline..."
# Use setup_intellij_project util which handles startup, trust dialogs, etc.
# We modify it slightly to NOT wait forever since we want to modify the file while it's running
su - ga -c "DISPLAY=:1 /opt/idea/bin/idea.sh '$PROJECT_DIR' > /tmp/idea_startup.log 2>&1 &"

# Wait for project load (using task_utils function or manual check)
wait_for_project_loaded "fintech-core" 120

# Handle initial dialogs
handle_trust_dialog 5
dismiss_dialogs 3

# Wait extra time for Local History to index and save the file state
echo "Waiting for Local History to index..."
sleep 20

# 4. The Accident: Overwrite the file externally
echo "Simulating accidental overwrite..."
cat > "$FILE_PATH" << 'EOF'
package com.fintech.core;

/**
 * Validates financial transactions against tier limits.
 */
public class TransactionValidator {

    // TODO: Implement validation logic
    // I need to look up the tier limits again...
    
    public boolean validate(Transaction tx, UserTier tier) {
        return true;
    }
}
EOF
chown ga:ga "$FILE_PATH"

# 5. Force IntelliJ to detect the change
# Focus window and send 'Synchronize' shortcut (Ctrl+Alt+Y)
focus_intellij_window
sleep 1
DISPLAY=:1 xdotool key ctrl+alt+y 2>/dev/null || true
sleep 2

# Take initial screenshot (showing the stub/broken state)
take_screenshot /tmp/task_start.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="