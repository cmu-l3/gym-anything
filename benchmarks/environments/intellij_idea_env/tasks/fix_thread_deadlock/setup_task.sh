#!/bin/bash
set -e
echo "=== Setting up fix_thread_deadlock task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/banking-core"

# 1. Create Project Structure
echo "Generating banking-core project..."
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java/com/bank/core"
mkdir -p "$PROJECT_DIR/src/test/java/com/bank/core"

# 2. Create POM
cat > "$PROJECT_DIR/pom.xml" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.bank</groupId>
  <artifactId>banking-core</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.13.2</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
EOF

# 3. Create Account Class (The Buggy Code)
cat > "$PROJECT_DIR/src/main/java/com/bank/core/Account.java" <<EOF
package com.bank.core;

public class Account {
    private final int id;
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

    // BUG: This method acquires locks in an inconsistent order, causing deadlock
    // when two threads transfer between the same accounts in opposite directions.
    public void transfer(Account target, double amount) {
        // Lock this account first
        synchronized (this) {
            try {
                // Simulation of processing time to increase deadlock probability
                Thread.sleep(10);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }

            // Then lock the target account
            synchronized (target) {
                if (this.balance >= amount) {
                    this.balance -= amount;
                    target.balance += amount;
                }
            }
        }
    }
}
EOF

# 4. Create Deadlock Demo (Reproducer)
cat > "$PROJECT_DIR/src/main/java/com/bank/core/DeadlockDemo.java" <<EOF
package com.bank.core;

public class DeadlockDemo {
    public static void main(String[] args) {
        final Account a1 = new Account(1, 1000);
        final Account a2 = new Account(2, 1000);

        System.out.println("Starting concurrent transfers...");

        Thread t1 = new Thread(() -> {
            for (int i = 0; i < 5; i++) {
                a1.transfer(a2, 10);
                System.out.println("Transferred A -> B");
            }
        });

        Thread t2 = new Thread(() -> {
            for (int i = 0; i < 5; i++) {
                a2.transfer(a1, 10);
                System.out.println("Transferred B -> A");
            }
        });

        t1.start();
        t2.start();

        try {
            t1.join();
            t2.join();
            System.out.println("Transfers completed successfully!");
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }
}
EOF

# 5. Create Test Suite (Verification)
cat > "$PROJECT_DIR/src/test/java/com/bank/core/AccountTest.java" <<EOF
package com.bank.core;

import org.junit.Test;
import static org.junit.Assert.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

public class AccountTest {

    @Test(timeout = 10000)
    public void testDeadlockFreedom() throws InterruptedException {
        final Account a1 = new Account(1, 1000);
        final Account a2 = new Account(2, 1000);
        
        int threads = 4;
        ExecutorService executor = Executors.newFixedThreadPool(threads);
        CountDownLatch latch = new CountDownLatch(threads);
        
        // Concurrent transfers in random directions
        for (int i = 0; i < threads; i++) {
            final boolean direction = (i % 2 == 0);
            executor.submit(() -> {
                try {
                    for (int j = 0; j < 50; j++) {
                        if (direction) a1.transfer(a2, 1);
                        else a2.transfer(a1, 1);
                    }
                } finally {
                    latch.countDown();
                }
            });
        }
        
        boolean completed = latch.await(8, TimeUnit.SECONDS);
        executor.shutdownNow();
        assertTrue("Deadlock detected! Test timed out.", completed);
    }

    @Test
    public void testThreadSafety() throws InterruptedException {
        final Account a1 = new Account(1, 1000);
        final Account a2 = new Account(2, 1000);
        
        // High volume to catch race conditions if locks are removed
        int count = 1000;
        Thread t1 = new Thread(() -> {
            for (int i = 0; i < count; i++) a1.transfer(a2, 1);
        });
        Thread t2 = new Thread(() -> {
            for (int i = 0; i < count; i++) a2.transfer(a1, 1);
        });
        
        t1.start();
        t2.start();
        t1.join();
        t2.join();
        
        assertEquals("Total balance should remain 2000", 2000.0, a1.getBalance() + a2.getBalance(), 0.001);
    }
}
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record initial state for verification
# We record the md5 of Account.java to check if it changes later
md5sum "$PROJECT_DIR/src/main/java/com/bank/core/Account.java" > /tmp/initial_account_hash.txt

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Open the project in IntelliJ
setup_intellij_project "$PROJECT_DIR" "banking-core" 120

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="