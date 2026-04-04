#!/bin/bash
set -e
echo "=== Setting up Remote Debug Task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/PaymentGateway"
SRC_DIR="$PROJECT_DIR/src/main/java/com/example/gateway"
mkdir -p "$SRC_DIR"

# 1. Create the Java Source Code
cat > "$SRC_DIR/TransactionProcessor.java" << 'JAVAEOF'
package com.example.gateway;

import java.io.FileWriter;
import java.io.IOException;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import java.util.Random;

public class TransactionProcessor {
    public static void main(String[] args) throws InterruptedException, IOException {
        // Generate a random secret token that persists for the process lifetime
        String randomPart = UUID.randomUUID().toString().substring(0, 8).toUpperCase();
        String transactionToken = "TOKEN-" + randomPart;
        
        // Write to a hidden file for verification (Ground Truth)
        // Agent cannot easily find this as it is outside the project and hidden
        try (FileWriter fw = new FileWriter("/tmp/.ground_truth_token")) {
            fw.write(transactionToken);
        }
        
        System.out.println("Transaction Processor Started. Listening for debugger on port 5005...");
        System.out.println("Processing transactions...");
        
        int id = 1000;
        Random rand = new Random();
        
        while (true) {
            // Simulate processing work
            processTransaction(id++, transactionToken, rand.nextDouble() * 1000);
            TimeUnit.SECONDS.sleep(3); 
        }
    }

    private static void processTransaction(int id, String token, double amount) {
        // The agent needs to break here to see 'token'
        String status = "PROCESSING";
        if (amount > 800) status = "HIGH_VALUE";
        
        // Use the token in a way that doesn't print it to stdout
        // This ensures the agent MUST debug to see it
        String secureHash = Integer.toHexString((token + amount).hashCode());
        
        System.out.println("Tx " + id + " [" + status + "]: " + secureHash);
    }
}
JAVAEOF

# 2. Create POM.xml to make it a valid Maven project for IntelliJ
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>payment-gateway</artifactId>
    <version>1.0-SNAPSHOT</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
</project>
POMEOF

chown -R ga:ga "$PROJECT_DIR"

# 3. Compile the code manually for the background process
echo "Compiling background process..."
mkdir -p /tmp/classes
javac -d /tmp/classes "$SRC_DIR/TransactionProcessor.java"

# 4. Start the background process with JDWP enabled
echo "Starting background process with JDWP on port 5005..."
# -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005
# suspend=n means it starts running immediately without waiting for debugger
nohup java -cp /tmp/classes \
    -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005 \
    com.example.gateway.TransactionProcessor \
    > /tmp/transaction_processor.log 2>&1 &

BG_PID=$!
echo "Background process started (PID: $BG_PID)"

# 5. Wait for port 5005 to be open
echo "Waiting for port 5005..."
for i in {1..30}; do
    if netstat -tln | grep -q ":5005 "; then
        echo "Port 5005 is open."
        break
    fi
    sleep 1
done

# 6. Open IntelliJ with the project
setup_intellij_project "$PROJECT_DIR" "PaymentGateway" 120

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="