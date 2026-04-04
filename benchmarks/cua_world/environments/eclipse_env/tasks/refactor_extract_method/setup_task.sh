#!/bin/bash
set -e
echo "=== Setting up Refactor: Extract Method task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="CorporateReporting"
PROJECT_DIR="/home/ga/eclipse-workspace/$PROJECT_NAME"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create Project Directory
mkdir -p "$PROJECT_DIR/src/main/java/com/corp/reporting"
mkdir -p "$PROJECT_DIR/src/test/java/com/corp/reporting"
mkdir -p "$PROJECT_DIR/target/classes"

# 2. Create POM
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.corp</groupId>
  <artifactId>reporting</artifactId>
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
EOF

# 3. Create Eclipse .project file (so it opens immediately)
cat > "$PROJECT_DIR/.project" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>$PROJECT_NAME</name>
    <comment></comment>
    <projects>
    </projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments>
            </arguments>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
            <arguments>
            </arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
EOF

# 4. Create Eclipse .classpath file
cat > "$PROJECT_DIR/.classpath" << 'EOF'
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
EOF

# 5. Create Source File with Duplication
cat > "$PROJECT_DIR/src/main/java/com/corp/reporting/ReportService.java" << 'EOF'
package com.corp.reporting;

import java.time.LocalDate;
import java.util.List;

public class ReportService {

    public String generateDailyReport(LocalDate date, List<String> transactions) {
        StringBuilder sb = new StringBuilder();
        
        // --- HEADER GENERATION ---
        sb.append("==========================================\n");
        sb.append("       ACME CORP - INTERNAL REPORT        \n");
        sb.append("==========================================\n");
        sb.append("Confidentiality: RESTRICTED ACCESS\n");
        sb.append("Generated on: ").append(LocalDate.now()).append("\n");
        sb.append("------------------------------------------\n");
        // -------------------------
        
        sb.append("Daily Activity for: ").append(date).append("\n");
        sb.append("Transaction Count: ").append(transactions.size()).append("\n");
        for (String tx : transactions) {
            sb.append(" - ").append(tx).append("\n");
        }
        
        return sb.toString();
    }

    public String generateWeeklyReport(LocalDate startDate, List<String> summaries) {
        StringBuilder sb = new StringBuilder();
        
        // --- HEADER GENERATION (DUPLICATED) ---
        sb.append("==========================================\n");
        sb.append("       ACME CORP - INTERNAL REPORT        \n");
        sb.append("==========================================\n");
        sb.append("Confidentiality: RESTRICTED ACCESS\n");
        sb.append("Generated on: ").append(LocalDate.now()).append("\n");
        sb.append("------------------------------------------\n");
        // --------------------------------------
        
        sb.append("Weekly Summary (Week of ").append(startDate).append(")\n");
        for (String summary : summaries) {
            sb.append(" * ").append(summary).append("\n");
        }
        sb.append("End of Report\n");
        
        return sb.toString();
    }
}
EOF

# 6. Create Test File
cat > "$PROJECT_DIR/src/test/java/com/corp/reporting/ReportServiceTest.java" << 'EOF'
package com.corp.reporting;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;
import java.time.LocalDate;
import java.util.Arrays;

public class ReportServiceTest {
    
    @Test
    public void testDailyReportContainsHeader() {
        ReportService service = new ReportService();
        String report = service.generateDailyReport(LocalDate.of(2023, 10, 1), Arrays.asList("Tx1", "Tx2"));
        
        assertTrue(report.contains("ACME CORP - INTERNAL REPORT"), "Header missing in daily report");
        assertTrue(report.contains("Confidentiality: RESTRICTED ACCESS"), "Confidentiality missing in daily report");
        assertTrue(report.contains("Daily Activity for:"), "Body missing in daily report");
    }

    @Test
    public void testWeeklyReportContainsHeader() {
        ReportService service = new ReportService();
        String report = service.generateWeeklyReport(LocalDate.of(2023, 10, 1), Arrays.asList("Sum1", "Sum2"));
        
        assertTrue(report.contains("ACME CORP - INTERNAL REPORT"), "Header missing in weekly report");
        assertTrue(report.contains("Weekly Summary"), "Body missing in weekly report");
    }
}
EOF

# Set Permissions
chown -R ga:ga "$PROJECT_DIR"

# Wait for Eclipse and ensure it's ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"
focus_eclipse_window
sleep 2

# Refresh workspace to ensure project is picked up
DISPLAY=:1 xdotool key F5
sleep 2

# Attempt to open the specific file to save the agent time
# Ctrl+Shift+R is "Open Resource"
echo "Opening ReportService.java..."
DISPLAY=:1 xdotool key ctrl+shift+r
sleep 1
DISPLAY=:1 xdotool type "ReportService"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

# Scroll to the area of interest
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type "10"
DISPLAY=:1 xdotool key Return

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task Setup Complete ==="