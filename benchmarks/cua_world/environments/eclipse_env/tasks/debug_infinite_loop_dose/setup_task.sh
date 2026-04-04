#!/bin/bash
set -e
echo "=== Setting up debug_infinite_loop_dose task ==="

source /workspace/scripts/task_utils.sh

# Define project paths
PROJECT_ROOT="/home/ga/eclipse-workspace/RayPlan"
SRC_DIR="$PROJECT_ROOT/src/main/java/com/rayplan"
PKG_CORE="$SRC_DIR/core"
PKG_MATH="$SRC_DIR/math"
PKG_MODEL="$SRC_DIR/model"
RESOURCES_DIR="$PROJECT_ROOT/src/main/resources"

# Clean up any previous runs
rm -rf "$PROJECT_ROOT" 2>/dev/null || true
rm -f "/home/ga/Desktop/dose_report.csv" 2>/dev/null || true
mkdir -p "$PKG_CORE" "$PKG_MATH" "$PKG_MODEL" "$RESOURCES_DIR"

# -----------------------------------------------------------------------------
# CREATE PROJECT FILES
# -----------------------------------------------------------------------------

# 1. pom.xml
cat > "$PROJECT_ROOT/pom.xml" << 'EOF_POM'
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.rayplan</groupId>
  <artifactId>RayPlan</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <maven.compiler.source>17</maven.compiler.source>
    <maven.compiler.target>17</maven.compiler.target>
  </properties>
</project>
EOF_POM

# 2. Eclipse .project file
cat > "$PROJECT_ROOT/.project" << 'EOF_PROJ'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>RayPlan</name>
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
EOF_PROJ

# 3. Eclipse .classpath file
cat > "$PROJECT_ROOT/.classpath" << 'EOF_CP'
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
EOF_CP

# 4. PatientCase.java (Model)
cat > "$PKG_MODEL/PatientCase.java" << 'EOF_JAVA'
package com.rayplan.model;

public class PatientCase {
    private String id;
    private double complexity;

    public PatientCase(String id, double complexity) {
        this.id = id;
        this.complexity = complexity;
    }

    public String getId() { return id; }
    public double getComplexity() { return complexity; }
    
    // Returns initial beam weights
    public double[] getInitialWeights() {
        return new double[] { 1.0, 1.0, 1.0, 1.0, 1.0 };
    }
}
EOF_JAVA

# 5. GradientDescentOptimizer.java (The Buggy File)
cat > "$PKG_MATH/GradientDescentOptimizer.java" << 'EOF_JAVA'
package com.rayplan.math;

import com.rayplan.model.PatientCase;

public class GradientDescentOptimizer {

    public static class OptimizationResult {
        public final double[] weights;
        public final double finalError;
        
        public OptimizationResult(double[] weights, double finalError) {
            this.weights = weights;
            this.finalError = finalError;
        }
    }

    public OptimizationResult optimize(PatientCase patient) {
        System.out.println("Starting optimization for " + patient.getId() + "...");
        
        double[] weights = patient.getInitialWeights();
        double error = Double.MAX_VALUE;
        double tolerance = 0.0001;
        
        // SIMULATED GRADIENT DESCENT LOGIC
        // BUG: For high complexity cases (Patient_003), this loop oscillates 
        // and never reaches tolerance < 0.0001
        
        while (error > tolerance) {
            // Update weights (dummy calculation)
            for (int i = 0; i < weights.length; i++) {
                weights[i] = weights[i] * 0.99;
            }
            
            // Calculate error
            if (patient.getComplexity() > 0.8) {
                // High complexity case: Error oscillates above tolerance
                // Simulating a local minima trap
                error = 0.0002 + (Math.sin(System.currentTimeMillis() / 100.0) * 0.00005);
            } else {
                // Normal convergence
                error = error * 0.8;
            }
            
            // Artificial delay to prevent CPU burning during simulation
            try { Thread.sleep(5); } catch (InterruptedException e) {}
            
            // DEBUG HINT: Uncomment to see error values
            // System.out.println("Current Error: " + error);
        }
        
        System.out.println("Optimization complete for " + patient.getId());
        return new OptimizationResult(weights, error);
    }
}
EOF_JAVA

# 6. BatchProcessor.java (Main Entry)
cat > "$PKG_CORE/BatchProcessor.java" << 'EOF_JAVA'
package com.rayplan.core;

import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;

import com.rayplan.math.GradientDescentOptimizer;
import com.rayplan.model.PatientCase;

public class BatchProcessor {

    public static void main(String[] args) {
        System.out.println("=== RayPlan Batch Dose Calculation System ===");
        
        List<PatientCase> batch = new ArrayList<>();
        batch.add(new PatientCase("Patient_001", 0.1));
        batch.add(new PatientCase("Patient_002", 0.4));
        batch.add(new PatientCase("Patient_003", 0.9)); // BUGGY CASE
        batch.add(new PatientCase("Patient_004", 0.2));
        batch.add(new PatientCase("Patient_005", 0.3));
        
        GradientDescentOptimizer optimizer = new GradientDescentOptimizer();
        String outputPath = System.getProperty("user.home") + "/Desktop/dose_report.csv";
        
        try (PrintWriter writer = new PrintWriter(new FileWriter(outputPath))) {
            writer.println("PatientID,FinalError,Status");
            
            for (PatientCase patient : batch) {
                System.out.println("Processing: " + patient.getId());
                try {
                    GradientDescentOptimizer.OptimizationResult result = optimizer.optimize(patient);
                    writer.printf("%s,%.6f,SUCCESS%n", patient.getId(), result.finalError);
                    writer.flush(); // Ensure we write partial results
                } catch (Exception e) {
                    writer.printf("%s,0.0,FAILED%n", patient.getId());
                }
            }
            System.out.println("Batch processing complete. Report saved to: " + outputPath);
            
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}
EOF_JAVA

# 7. Bug Report on Desktop
cat > "/home/ga/Desktop/bug_report.txt" << 'EOF_BUG'
BUG REPORT #9281
Title: System hangs during nightly batch processing
Severity: Critical

Description:
The RayPlan batch processor stops responding every night. Logs indicate it gets stuck on "Patient_003".
No exception is thrown; the process just hangs indefinitely.

Steps to Reproduce:
1. Run com.rayplan.core.BatchProcessor
2. Watch console output
3. Observe hang after "Processing: Patient_003"

Expected Behavior:
Optimization should complete or timeout if convergence fails.
EOF_BUG

# Fix permissions
chown -R ga:ga "$PROJECT_ROOT"
chown ga:ga "/home/ga/Desktop/bug_report.txt"

# -----------------------------------------------------------------------------
# ECLIPSE SETUP
# -----------------------------------------------------------------------------

# Wait for Eclipse to be ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Dismiss any dialogs
dismiss_dialogs 3
close_welcome_tab

# Focus and maximize Eclipse window
focus_eclipse_window
sleep 2

# Record timestamp
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="