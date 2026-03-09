#!/bin/bash
echo "=== Setting up package_executable_jar task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/csv-stats"
mkdir -p "$PROJECT_DIR/src/main/java/com/csvstats"
mkdir -p "$PROJECT_DIR/src/main/resources"

# 1. Create pom.xml (missing plugins)
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.csvstats</groupId>
    <artifactId>csv-stats</artifactId>
    <version>1.0</version>
    <packaging>jar</packaging>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.apache.commons</groupId>
            <artifactId>commons-csv</artifactId>
            <version>1.10.0</version>
        </dependency>
    </dependencies>

    <!-- TODO: Add build plugins to create executable JAR here -->
    
</project>
POMEOF

# 2. Create App.java
cat > "$PROJECT_DIR/src/main/java/com/csvstats/App.java" << 'JAVAEOF'
package com.csvstats;

import org.apache.commons.csv.CSVFormat;
import org.apache.commons.csv.CSVParser;
import org.apache.commons.csv.CSVRecord;
import java.io.FileReader;
import java.io.IOException;
import java.io.Reader;
import java.util.ArrayList;
import java.util.List;

public class App {
    public static void main(String[] args) {
        if (args.length < 1) {
            System.err.println("Usage: java -jar csv-stats.jar <csv-file>");
            System.exit(1);
        }

        String csvFile = args[0];
        System.out.println("Analyzing " + csvFile + "...");

        try (Reader reader = new FileReader(csvFile);
             CSVParser csvParser = new CSVParser(reader, CSVFormat.DEFAULT.withFirstRecordAsHeader())) {

            List<Double> populations = new ArrayList<>();

            for (CSVRecord record : csvParser) {
                String popStr = record.get("Population_2020");
                if (popStr != null && !popStr.isEmpty()) {
                    populations.add(Double.parseDouble(popStr.replace(",", "")));
                }
            }

            System.out.println("--- Statistics ---");
            System.out.println("Count: " + populations.size());
            System.out.println("Min: " + StatsCalculator.min(populations));
            System.out.println("Max: " + StatsCalculator.max(populations));
            System.out.println("Mean: " + StatsCalculator.mean(populations));

        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}
JAVAEOF

# 3. Create StatsCalculator.java
cat > "$PROJECT_DIR/src/main/java/com/csvstats/StatsCalculator.java" << 'JAVAEOF'
package com.csvstats;

import java.util.Collections;
import java.util.List;

public class StatsCalculator {
    public static double min(List<Double> data) {
        if (data.isEmpty()) return 0;
        return Collections.min(data);
    }

    public static double max(List<Double> data) {
        if (data.isEmpty()) return 0;
        return Collections.max(data);
    }

    public static double mean(List<Double> data) {
        if (data.isEmpty()) return 0;
        double sum = 0;
        for (Double d : data) sum += d;
        return sum / data.size();
    }
}
JAVAEOF

# 4. Create sample_data.csv (Real US Census Data snippet)
cat > "$PROJECT_DIR/src/main/resources/sample_data.csv" << 'CSVEOF'
State,Population_2020,Population_2021
Alabama,5024279,5039877
Alaska,733391,732673
Arizona,7151502,7276316
Arkansas,3011524,3025891
California,39538223,39237836
Colorado,5773714,5812069
Connecticut,3605944,3605597
Delaware,989948,1003384
Florida,21538187,21781128
Georgia,10711908,10799566
Hawaii,1455271,1441553
Idaho,1839106,1900923
Illinois,12812508,12671469
Indiana,6785528,6805985
CSVEOF

chown -R ga:ga "$PROJECT_DIR"

# 5. Pre-resolve dependencies (so agent doesn't spend time downloading)
echo "Pre-resolving dependencies..."
run_maven "$PROJECT_DIR" "dependency:resolve"
run_maven "$PROJECT_DIR" "compile"

# 6. Record initial state (verify no executable jar exists yet)
rm -f "$PROJECT_DIR/target/csv-stats-1.0.jar" 2>/dev/null
date +%s > /tmp/task_start_time.txt

# 7. Open IntelliJ
setup_intellij_project "$PROJECT_DIR" "csv-stats" 120

# 8. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="