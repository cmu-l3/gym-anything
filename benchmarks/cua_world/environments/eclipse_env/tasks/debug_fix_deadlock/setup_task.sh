#!/bin/bash
set -e
echo "=== Setting up debug_fix_deadlock task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define Project Paths
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_NAME="FinancialSystem"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# Clean up previous runs
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/financial/core"
mkdir -p "$PROJECT_DIR/src/main/java/com/financial/simulation"
mkdir -p "$PROJECT_DIR/bin"

# --- Create Source Files ---

# 1. Account.java
cat > "$PROJECT_DIR/src/main/java/com/financial/core/Account.java" << 'JAVA'
package com.financial.core;

public class Account {
    private int id;
    private double balance;

    public Account(int id, double balance) {
        this.id = id;
        this.balance = balance;
    }

    public int getId() {
        return id;
    }

    public double getBalance() {
        return balance;
    }

    public void debit(double amount) {
        this.balance -= amount;
    }

    public void credit(double amount) {
        this.balance += amount;
    }
}
JAVA

# 2. TransferService.java (BROKEN - DEADLOCK PRONE)
cat > "$PROJECT_DIR/src/main/java/com/financial/core/TransferService.java" << 'JAVA'
package com.financial.core;

public class TransferService {

    /**
     * Transfers amount from one account to another.
     * WARNING: This implementation is not thread-safe and may deadlock.
     */
    public void transfer(Account from, Account to, double amount) {
        // Locking order depends on argument order - prone to deadlock!
        synchronized(from) {
            try {
                // Simulate some IO or processing delay to widen the race window
                Thread.sleep(50); 
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            
            synchronized(to) {
                from.debit(amount);
                to.credit(amount);
                System.out.println("Transferred " + amount + " from " + from.getId() + " to " + to.getId());
            }
        }
    }
}
JAVA

# 3. DeadlockDemo.java (Simulation Runner)
cat > "$PROJECT_DIR/src/main/java/com/financial/simulation/DeadlockDemo.java" << 'JAVA'
package com.financial.simulation;

import com.financial.core.Account;
import com.financial.core.TransferService;

public class DeadlockDemo {

    public static void main(String[] args) throws InterruptedException {
        System.out.println("Starting Simulation...");
        
        final Account a = new Account(1, 1000);
        final Account b = new Account(2, 1000);
        final TransferService service = new TransferService();
        
        // Thread A moves money from A to B
        Thread t1 = new Thread(() -> {
            for(int i=0; i<20; i++) {
                service.transfer(a, b, 10);
            }
        }, "Transfer-Worker-A");
        
        // Thread B moves money from B to A
        Thread t2 = new Thread(() -> {
            for(int i=0; i<20; i++) {
                service.transfer(b, a, 10);
            }
        }, "Transfer-Worker-B");
        
        t1.start();
        t2.start();
        
        t1.join();
        t2.join();
        
        System.out.println("SIMULATION COMPLETED");
    }
}
JAVA

# --- Create Eclipse Project Metadata ---

# .project
cat > "$PROJECT_DIR/.project" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>FinancialSystem</name>
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
XML

# .classpath
cat > "$PROJECT_DIR/.classpath" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src/main/java"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
XML

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Wait for Eclipse to be ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Focus and maximize Eclipse window
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
echo "Project created at $PROJECT_DIR"