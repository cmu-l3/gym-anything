#!/bin/bash
set -e
echo "=== Setting up configure_run_app task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define project paths
PROJECT_DIR="/home/ga/IdeaProjects/DataProcessor"
SRC_DIR="$PROJECT_DIR/src/main/java/com/dataproc"
DATA_DIR="$PROJECT_DIR/data"

# Clean up previous state
rm -rf "$PROJECT_DIR"
rm -rf "/home/ga/output"
mkdir -p "$SRC_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "/home/ga/output"

# 1. Create pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.dataproc</groupId>
  <artifactId>DataProcessor</artifactId>
  <packaging>jar</packaging>
  <version>1.0-SNAPSHOT</version>
  <name>DataProcessor</name>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
  <dependencies>
    <dependency>
      <groupId>com.fasterxml.jackson.core</groupId>
      <artifactId>jackson-databind</artifactId>
      <version>2.15.2</version>
    </dependency>
  </dependencies>
</project>
POMEOF

# 2. Create Java Source Code
# App.java
cat > "$SRC_DIR/App.java" << 'JAVAEOF'
package com.dataproc;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.List;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;

public class App {
    public static void main(String[] args) {
        System.out.println("Starting DataProcessor...");

        // 1. Check Arguments
        if (args.length < 1) {
            System.err.println("ERROR: Missing input file argument.");
            System.err.println("Usage: java com.dataproc.App <input_csv_path>");
            System.exit(1);
        }
        String inputFile = args[0];

        // 2. Check System Properties (VM Options)
        String speciesFilter = System.getProperty("filter.species");
        String minPetalLenStr = System.getProperty("filter.min.petal.length");
        String outputFormat = System.getProperty("output.format", "csv"); // Default to csv if not set

        if (speciesFilter == null || minPetalLenStr == null) {
            System.err.println("ERROR: Missing required system properties.");
            System.err.println("Please set -Dfilter.species=<species> and -Dfilter.min.petal.length=<value>");
            System.exit(1);
        }

        double minPetalLen = Double.parseDouble(minPetalLenStr);

        // 3. Check Environment Variables
        String outputDir = System.getenv("OUTPUT_DIR");
        String logLevel = System.getenv("LOG_LEVEL");

        if (outputDir == null) {
            System.err.println("ERROR: OUTPUT_DIR environment variable not set.");
            System.exit(1);
        }

        System.out.println("Configuration:");
        System.out.println("- Input: " + inputFile);
        System.out.println("- Output Dir: " + outputDir);
        System.out.println("- Filter Species: " + speciesFilter);
        System.out.println("- Filter Min Petal Length: " + minPetalLen);
        System.out.println("- Log Level: " + (logLevel != null ? logLevel : "DEFAULT"));

        // 4. Process Data
        List<IrisRecord> records = new ArrayList<>();
        int totalRead = 0;

        try (BufferedReader br = new BufferedReader(new FileReader(inputFile))) {
            String line;
            while ((line = br.readLine()) != null) {
                if (line.trim().isEmpty()) continue;
                // Handle basic CSV parsing (Iris dataset has no header usually, or we skip it)
                String[] parts = line.split(",");
                if (parts.length < 5) continue;

                try {
                    // UCI Iris format: sepal_length,sepal_width,petal_length,petal_width,species
                    double sl = Double.parseDouble(parts[0]);
                    double sw = Double.parseDouble(parts[1]);
                    double pl = Double.parseDouble(parts[2]);
                    double pw = Double.parseDouble(parts[3]);
                    String sp = parts[4];
                    // UCI data usually has "Iris-virginica", remove prefix if needed or match exact
                    // We will match contains for robustness
                    
                    totalRead++;

                    if (sp.contains(speciesFilter) && pl >= minPetalLen) {
                        records.add(new IrisRecord(sl, sw, pl, pw, sp));
                    }
                } catch (NumberFormatException e) {
                    // Skip header or bad lines
                }
            }
        } catch (Exception e) {
            System.err.println("Error reading file: " + e.getMessage());
            System.exit(1);
        }

        System.out.println("Processed " + totalRead + " records. Filtered down to " + records.size());

        // 5. Write Output
        try {
            File outDirFile = new File(outputDir);
            if (!outDirFile.exists()) outDirFile.mkdirs();

            File outFile = new File(outDirFile, "iris_filtered.json");
            ObjectMapper mapper = new ObjectMapper();
            mapper.enable(SerializationFeature.INDENT_OUTPUT);
            mapper.writeValue(outFile, records);
            System.out.println("Output written to: " + outFile.getAbsolutePath());

        } catch (Exception e) {
            System.err.println("Error writing output: " + e.getMessage());
            System.exit(1);
        }
    }
}
JAVAEOF

# IrisRecord.java
cat > "$SRC_DIR/IrisRecord.java" << 'JAVAEOF'
package com.dataproc;

public class IrisRecord {
    public double sepal_length;
    public double sepal_width;
    public double petal_length;
    public double petal_width;
    public String species;

    public IrisRecord() {}

    public IrisRecord(double sl, double sw, double pl, double pw, String sp) {
        this.sepal_length = sl;
        this.sepal_width = sw;
        this.petal_length = pl;
        this.petal_width = pw;
        this.species = sp;
    }
}
JAVAEOF

# 3. Download Real Data
echo "Downloading Iris dataset..."
# Try curl with fallback
if ! curl -L -o "$DATA_DIR/iris.csv" "https://archive.ics.uci.edu/ml/machine-learning-databases/iris/iris.data"; then
    echo "Primary download failed, using backup source..."
    # Fallback to a backup URL or embedded data if network fails completely (omitted for brevity, assume net works)
    # Simple backup: just generate dummy real-looking data if curl fails (last resort)
    cat > "$DATA_DIR/iris.csv" << 'CSVEOF'
5.1,3.5,1.4,0.2,Iris-setosa
6.3,3.3,6.0,2.5,Iris-virginica
5.8,2.7,5.1,1.9,Iris-virginica
7.1,3.0,5.9,2.1,Iris-virginica
4.9,3.0,1.4,0.2,Iris-setosa
CSVEOF
fi

# 4. Create Documentation
cat > "$PROJECT_DIR/README_RUN.md" << 'MDEOF'
# DataProcessor Configuration

To run this application, you must configure the Run/Debug settings in IntelliJ as follows:

## Run Configuration Settings

1.  **Type:** Application
2.  **Name:** `ProcessIrisData`
3.  **Main Class:** `com.dataproc.App`

## Parameters

### VM Options
You must set memory limits and system properties for filtering: