#!/bin/bash
set -e
echo "=== Setting up Debug Conditional Breakpoint Task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="DataBatchAnalyzer"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"
SOURCE_DIR="$PROJECT_DIR/src/main/java/com/example"
mkdir -p "$SOURCE_DIR"

# Generate a random seed for this run to ensure the value changes every time
SEED=$(date +%s%N)
TARGET_ITERATION=888

echo "Generating project with Seed: $SEED"

# 1. Create the Main.java file
cat > "$SOURCE_DIR/Main.java" << JAVAEOF
package com.example;

import java.util.Random;

public class Main {
    public static void main(String[] args) {
        new DataBatchAnalyzer().processData();
    }
}

class DataBatchAnalyzer {
    // Seed generated for this specific task instance
    private static final long SEED = ${SEED}L;

    public void processData() {
        Random random = new Random(SEED);
        double currentProcessValue = 0.0;

        System.out.println("Starting batch processing...");

        for (int i = 0; i < 1000; i++) {
            // Complex calculation simulation
            double noise = random.nextGaussian();
            double factor = Math.sin(i * 0.1);
            
            // This is the variable the agent needs to inspect
            currentProcessValue = factor * Math.cos(noise) + Math.log(Math.abs(noise) + 1.0);

            // Simulate some processing time
            try { 
                Thread.sleep(2); 
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }

            if (i % 100 == 0) {
                System.out.println("Processed " + i + " records...");
            }
        }
        System.out.println("Processing complete.");
    }
}
JAVAEOF

# 2. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << POMEOF
<project xmlns="http://maven.apache.org/POM/4.0.0" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>data-batch-analyzer</artifactId>
    <version>1.0-SNAPSHOT</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
</project>
POMEOF

# 3. Calculate the Ground Truth (Hidden from Agent)
# We create a temporary solver to run the math and extract the value at index 888
echo "Calculating ground truth..."
cat > "$PROJECT_DIR/Solver.java" << SOLVEREOF
package com.example;
import java.util.Random;
public class Solver {
    public static void main(String[] args) {
        long SEED = ${SEED}L;
        Random random = new Random(SEED);
        double currentProcessValue = 0.0;
        for (int i = 0; i < 1000; i++) {
            double noise = random.nextGaussian();
            double factor = Math.sin(i * 0.1);
            currentProcessValue = factor * Math.cos(noise) + Math.log(Math.abs(noise) + 1.0);
            
            if (i == ${TARGET_ITERATION}) {
                System.out.println(currentProcessValue);
                break;
            }
        }
    }
}
SOLVEREOF

# Compile and run the solver
mkdir -p "$PROJECT_DIR/target/classes"
javac -d "$PROJECT_DIR/target/classes" "$PROJECT_DIR/Solver.java"
GROUND_TRUTH_VAL=$(java -cp "$PROJECT_DIR/target/classes" com.example.Solver)

# Save ground truth to a hidden location
mkdir -p /var/lib/task
echo "$GROUND_TRUTH_VAL" > /var/lib/task/ground_truth.txt
chmod 600 /var/lib/task/ground_truth.txt

echo "Ground Truth for i=$TARGET_ITERATION: $GROUND_TRUTH_VAL"

# Cleanup solver
rm "$PROJECT_DIR/Solver.java"
rm -rf "$PROJECT_DIR/target"

# 4. Set permissions and ownership
chown -R ga:ga "$PROJECT_DIR"

# Compute hash of the source file BEFORE the task starts (to detect modification)
md5sum "$SOURCE_DIR/Main.java" | awk '{print $1}' > /var/lib/task/original_source_hash.txt

# Make the source file read-only to discourage editing (Agent can chmod it back, but we will catch them via hash check)
chmod 444 "$SOURCE_DIR/Main.java"

# 5. Open IntelliJ
setup_intellij_project "$PROJECT_DIR" "DataBatchAnalyzer" 120

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="