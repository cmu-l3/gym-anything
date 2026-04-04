#!/bin/bash
set -e
echo "=== Setting up Debug Conditional Breakpoint Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
PROJECT_NAME="FinancialAudit"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# Clean up previous runs
rm -rf "$PROJECT_DIR"
rm -f /home/ga/solution.txt

# Create project structure
mkdir -p "$PROJECT_DIR/src/main/java/com/audit/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/audit/logic"
mkdir -p "$PROJECT_DIR/bin"

# 1. Create .project file
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>FinancialAudit</name>
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
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOF

# 3. Create Transaction.java
cat > "$PROJECT_DIR/src/main/java/com/audit/model/Transaction.java" << 'EOF'
package com.audit.model;

import java.math.BigDecimal;

public class Transaction {
    private final String id;
    private final BigDecimal amount;
    private final String type;

    public Transaction(String id, BigDecimal amount, String type) {
        this.id = id;
        this.amount = amount;
        this.type = type;
    }

    public String getId() { return id; }
    public BigDecimal getAmount() { return amount; }
    public String getType() { return type; }

    @Override
    public String toString() {
        return "Transaction{id='" + id + "', amount=" + amount + "}";
    }
}
EOF

# 4. Create ComplexMath.java (Hidden logic with the bug)
cat > "$PROJECT_DIR/src/main/java/com/audit/logic/ComplexMath.java" << 'EOF'
package com.audit.logic;

import java.math.BigDecimal;
import com.audit.model.Transaction;

public class ComplexMath {
    // Deterministic simulation of a complex calculation
    public static BigDecimal calculateBalanceImpact(Transaction tx, BigDecimal currentBalance) {
        // Normal processing
        BigDecimal impact = tx.getAmount();
        
        // Simulating a data-dependent bug:
        // Transaction TX-3842 triggers a massive deduction due to a "glitch"
        if (tx.getId().equals("TX-3842")) {
            return currentBalance.subtract(new BigDecimal("1000000")); // Causes negative balance
        }
        
        return currentBalance.add(impact);
    }
}
EOF

# 5. Create FinancialBatchProcessor.java (Main Loop)
cat > "$PROJECT_DIR/src/main/java/com/audit/FinancialBatchProcessor.java" << 'EOF'
package com.audit;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import com.audit.model.Transaction;
import com.audit.logic.ComplexMath;

public class FinancialBatchProcessor {

    public static void main(String[] args) {
        System.out.println("Starting Batch Processing...");
        List<Transaction> batch = generateBatch(5000);
        
        BigDecimal currentBalance = new BigDecimal("50000.00");
        
        for (int i = 0; i < batch.size(); i++) {
            Transaction currentTransaction = batch.get(i);
            
            // --- LOGIC START ---
            // Calculate new balance based on transaction
            currentBalance = ComplexMath.calculateBalanceImpact(currentTransaction, currentBalance);
            
            // Checkpoint (User should set breakpoint here)
            processDownstream(currentBalance);
            // --- LOGIC END ---
        }
        
        System.out.println("Batch Complete. Final Balance: " + currentBalance);
    }
    
    private static void processDownstream(BigDecimal balance) {
        // In a real system, this might write to DB
        // It handles negative values silently, hiding the bug
        if (balance.compareTo(BigDecimal.ZERO) < 0) {
            // Error is swallowed here in logs
            // System.err.println("Warning: internal adjustment made.");
        }
    }
    
    private static List<Transaction> generateBatch(int count) {
        List<Transaction> list = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            String id = "TX-" + i;
            BigDecimal amt = new BigDecimal(100 + (i % 50));
            list.add(new Transaction(id, amt, "CREDIT"));
        }
        return list;
    }
}
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Calculate initial hashes for integrity verification
# This prevents "printf debugging" (modifying code to print the answer)
echo "Calculating initial source code hashes..."
find "$PROJECT_DIR" -name "*.java" -type f -exec md5sum {} \; | sort > /tmp/initial_hashes.txt
chown ga:ga /tmp/initial_hashes.txt

# Ensure Eclipse is running
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="