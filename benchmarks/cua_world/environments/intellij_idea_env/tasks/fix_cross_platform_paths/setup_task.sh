#!/bin/bash
echo "=== Setting up fix_cross_platform_paths task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/path-issues"
mkdir -p "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/data"
mkdir -p "$PROJECT_DIR/src/main/java/com/example/paths"
mkdir -p "$PROJECT_DIR/src/main/resources"
mkdir -p "$PROJECT_DIR/output"

# 1. Create POM
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>path-issues</artifactId>
    <version>1.0-SNAPSHOT</version>
    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>
    <build>
        <plugins>
            <plugin>
                <groupId>org.codehaus.mojo</groupId>
                <artifactId>exec-maven-plugin</artifactId>
                <version>3.1.0</version>
                <configuration>
                    <mainClass>com.example.paths.Main</mainClass>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
POMEOF

# 2. Create Realistic Data (Inventory CSV)
echo "ID,Product,Category,Price,Stock" > "$PROJECT_DIR/data/inventory.csv"
for i in {1..50}; do
    P=$((RANDOM % 100))
    S=$((RANDOM % 500))
    echo "$i,Widget-$i,Electronics,$P.99,$S" >> "$PROJECT_DIR/data/inventory.csv"
done

# 3. Create Config (Lowercase filename)
cat > "$PROJECT_DIR/src/main/resources/config.properties" << 'CONFEOF'
app.name=InventoryProcessor
app.version=1.0.0
report.header=Inventory Summary Report
CONFEOF

# 4. Create Broken Main.java
cat > "$PROJECT_DIR/src/main/java/com/example/paths/Main.java" << 'JAVAEOF'
package com.example.paths;

import java.io.*;
import java.nio.file.*;
import java.util.*;

public class Main {
    public static void main(String[] args) {
        System.out.println("Starting Inventory Processor...");
        
        // BUG 1: Hardcoded Windows absolute path
        String inputPath = "C:\\Users\\Dev\\Documents\\path-issues\\data\\inventory.csv";
        
        // BUG 2: Hardcoded Windows path separator
        String outputPath = "output\\report.txt";

        try {
            ConfigLoader config = new ConfigLoader();
            System.out.println("Loaded configuration: " + config.getProperty("app.name"));

            processData(inputPath, outputPath);
            System.out.println("Processing complete. Report saved to " + outputPath);
            
        } catch (Exception e) {
            System.err.println("Error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }

    private static void processData(String input, String output) throws IOException {
        // Simple logic to demonstrate file I/O
        File inFile = new File(input);
        if (!inFile.exists()) {
            throw new FileNotFoundException("Could not find input file: " + input);
        }
        
        List<String> lines = Files.readAllLines(inFile.toPath());
        int count = lines.size() - 1; // subtract header
        
        File outFile = new File(output);
        // Ensure parent exists
        if (outFile.getParentFile() != null) {
            outFile.getParentFile().mkdirs();
        }
        
        try (PrintWriter writer = new PrintWriter(outFile)) {
            writer.println("Report Generated: " + new Date());
            writer.println("Total Items: " + count);
            writer.println("Source: " + input);
        }
    }
}
JAVAEOF

# 5. Create Broken ConfigLoader.java
cat > "$PROJECT_DIR/src/main/java/com/example/paths/ConfigLoader.java" << 'JAVAEOF'
package com.example.paths;

import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;

public class ConfigLoader {
    private final Properties props = new Properties();

    public ConfigLoader() throws IOException {
        // BUG 3: Case sensitivity (file is config.properties)
        // This works on Windows (sometimes) but fails on Linux
        String configFileName = "Config.properties";
        
        try (InputStream input = getClass().getClassLoader().getResourceAsStream(configFileName)) {
            if (input == null) {
                throw new IOException("Sorry, unable to find " + configFileName);
            }
            props.load(input);
        }
    }

    public String getProperty(String key) {
        return props.getProperty(key);
    }
}
JAVAEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Calculate initial hashes to track changes
md5sum "$PROJECT_DIR/src/main/java/com/example/paths/Main.java" > /tmp/initial_main_hash.txt
md5sum "$PROJECT_DIR/src/main/java/com/example/paths/ConfigLoader.java" > /tmp/initial_config_hash.txt

# Start IntelliJ
setup_intellij_project "$PROJECT_DIR" "path-issues" 120

# Record task start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="