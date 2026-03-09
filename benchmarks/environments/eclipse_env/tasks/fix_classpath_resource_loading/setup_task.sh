#!/bin/bash
set -e
echo "=== Setting up fix_classpath_resource_loading task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/ClimateData"
mkdir -p "$PROJECT_DIR/src/main/java/com/climate"
mkdir -p "$PROJECT_DIR/src/main/resources"
mkdir -p "$PROJECT_DIR/src/test/java/com/climate"

# 1. Download Real Data (NASA GISTEMP)
# Fallback to embedded data if download fails
DATA_FILE="$PROJECT_DIR/src/main/resources/global_temps.csv"
echo "Downloading NASA GISTEMP data..."
if ! wget -q -O "$DATA_FILE" "https://data.giss.nasa.gov/gistemp/graphs/graph_data/Global_Mean_Estimates_based_on_Land_and_Ocean_Data/graph.csv"; then
    echo "Network download failed, using fallback data..."
    cat > "$DATA_FILE" << 'CSVEOF'
Year,No_Smoothing,Lowess(5)
1880,-0.16,-0.09
1881,-0.08,-0.13
1882,-0.11,-0.17
1883,-0.17,-0.20
1884,-0.28,-0.24
1885,-0.33,-0.26
1886,-0.31,-0.27
1887,-0.36,-0.27
1888,-0.20,-0.26
1889,-0.10,-0.25
1890,-0.35,-0.26
1900,-0.07,-0.15
1950,-0.17,-0.09
2000,0.39,0.43
2020,1.01,0.92
2023,1.17,1.05
CSVEOF
else
    # The NASA file has a header preamble we might want to clean up or just handle in code
    # Usually it starts with "Year,No_Smoothing..." after some lines, or just headers.
    # Let's ensure it's clean for the task simplicity (skip first line if it's metadata)
    # Actually, let's keep it real. The code should handle skipping header.
    true
fi

# 2. Create the Buggy Java Class
cat > "$PROJECT_DIR/src/main/java/com/climate/ClimateAnalyzer.java" << 'JAVAEOF'
package com.climate;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

public class ClimateAnalyzer {

    public List<Double> loadTemperatureAnomalies() throws IOException {
        List<Double> anomalies = new ArrayList<>();
        
        // BUG: Hardcoded filesystem path. 
        // FAILS if run from outside project root or if packaged as JAR.
        File file = new File("src/main/resources/global_temps.csv");
        
        if (!file.exists()) {
            System.err.println("File not found at: " + file.getAbsolutePath());
            throw new IOException("Data file not found: " + file.getPath());
        }

        try (BufferedReader br = new BufferedReader(new FileReader(file))) {
            String line;
            int lineCount = 0;
            while ((line = br.readLine()) != null) {
                lineCount++;
                // Skip header or metadata
                if (lineCount < 2 || !Character.isDigit(line.charAt(0))) {
                    continue;
                }
                
                try {
                    String[] parts = line.split(",");
                    if (parts.length >= 2) {
                        anomalies.add(Double.parseDouble(parts[1]));
                    }
                } catch (NumberFormatException e) {
                    // Ignore malformed lines
                }
            }
        }
        return anomalies;
    }

    public static void main(String[] args) {
        try {
            ClimateAnalyzer analyzer = new ClimateAnalyzer();
            List<Double> data = analyzer.loadTemperatureAnomalies();
            System.out.println("Successfully loaded " + data.size() + " records.");
            if (!data.isEmpty()) {
                System.out.println("First record: " + data.get(0));
                System.out.println("Last record: " + data.get(data.size() - 1));
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
JAVAEOF

# 3. Create the Test Class
cat > "$PROJECT_DIR/src/test/java/com/climate/ClimateAnalyzerTest.java" << 'TESTEOF'
package com.climate;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;
import java.io.IOException;
import java.util.List;

public class ClimateAnalyzerTest {

    @Test
    public void testLoadData() {
        ClimateAnalyzer analyzer = new ClimateAnalyzer();
        try {
            List<Double> data = analyzer.loadTemperatureAnomalies();
            assertNotNull(data, "Data list should not be null");
            assertTrue(data.size() > 0, "Should load at least one record");
            System.out.println("Test passed: Loaded " + data.size() + " records");
        } catch (IOException e) {
            fail("Should not throw IOException: " + e.getMessage());
        }
    }
}
TESTEOF

# 4. Create Maven POM
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.climate</groupId>
    <artifactId>climate-data</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.0</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
POMEOF

# 5. Create Eclipse Project Files
cat > "$PROJECT_DIR/.project" << 'PROJEOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>ClimateData</name>
    <comment></comment>
    <projects></projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments></arguments>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
            <arguments></arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
PROJEOF

cat > "$PROJECT_DIR/.classpath" << 'CPEOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="src" output="target/test-classes" path="src/test/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
            <attribute name="test" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
CPEOF

chown -R ga:ga "$PROJECT_DIR"

# Wait for Eclipse
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_start.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="