#!/bin/bash
set -e
echo "=== Setting up Refactor Parameterized Test task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
PROJECT_NAME="RadiationPhysics"
WORKSPACE_DIR="/home/ga/eclipse-workspace/$PROJECT_NAME"

# Clean up any previous run
rm -rf "$WORKSPACE_DIR" 2>/dev/null || true

# Create project structure
echo "Creating project structure..."
mkdir -p "$WORKSPACE_DIR/src/main/java/com/medtech/physics"
mkdir -p "$WORKSPACE_DIR/src/test/java/com/medtech/physics"

# Create pom.xml
cat > "$WORKSPACE_DIR/pom.xml" << 'EOFPOM'
<project xmlns="http://maven.apache.org/POM/4.0.0" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.medtech</groupId>
    <artifactId>radiation-physics</artifactId>
    <version>1.0.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.0</version>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.1.2</version>
            </plugin>
        </plugins>
    </build>
</project>
EOFPOM

# Create Source Class
cat > "$WORKSPACE_DIR/src/main/java/com/medtech/physics/DoseCalculator.java" << 'EOFSRC'
package com.medtech.physics;

/**
 * Calculates radiation dose for Linear Accelerator treatment plans.
 */
public class DoseCalculator {

    private static final double CALIBRATION_FACTOR = 1.0; // cGy/MU at dmax for 10x10 field

    /**
     * Calculate absolute dose in cGy.
     * 
     * @param monitorUnits The machine output setting (MU)
     * @param fieldOutputFactor Factor correcting for field size scatter (normalized to 1.0 at 10x10)
     * @return Calculated dose in Centigray (cGy)
     */
    public double calculateDose(double monitorUnits, double fieldOutputFactor) {
        if (monitorUnits < 0) {
            throw new IllegalArgumentException("Monitor Units cannot be negative");
        }
        return monitorUnits * CALIBRATION_FACTOR * fieldOutputFactor;
    }
}
EOFSRC

# Create Legacy Test Class (The one to be refactored)
cat > "$WORKSPACE_DIR/src/test/java/com/medtech/physics/DoseCalculatorTest.java" << 'EOFTEST'
package com.medtech.physics;

import static org.junit.jupiter.api.Assertions.assertEquals;
import org.junit.jupiter.api.Test;
// Hints for the agent (imports they will need)
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

public class DoseCalculatorTest {

    private final DoseCalculator calculator = new DoseCalculator();
    private final double DELTA = 0.001;

    // TODO: Refactor these repetitive tests into a single @ParameterizedTest

    @Test
    public void testDoseAt100MU() {
        double mu = 100.0;
        double outputFactor = 1.0; // 10x10cm
        double expected = 100.0;
        assertEquals(expected, calculator.calculateDose(mu, outputFactor), DELTA);
    }

    @Test
    public void testDoseAt200MU() {
        double mu = 200.0;
        double outputFactor = 1.0; // 10x10cm
        double expected = 200.0;
        assertEquals(expected, calculator.calculateDose(mu, outputFactor), DELTA);
    }

    @Test
    public void testDoseAt50MU() {
        double mu = 50.0;
        double outputFactor = 1.0;
        double expected = 50.0;
        assertEquals(expected, calculator.calculateDose(mu, outputFactor), DELTA);
    }

    @Test
    public void testDoseLargeField() {
        double mu = 150.0;
        double outputFactor = 1.045; // 20x20cm
        double expected = 156.75;
        assertEquals(expected, calculator.calculateDose(mu, outputFactor), DELTA);
    }

    @Test
    public void testDoseSmallField() {
        double mu = 300.0;
        double outputFactor = 0.892; // 4x4cm
        double expected = 267.6;
        assertEquals(expected, calculator.calculateDose(mu, outputFactor), DELTA);
    }
}
EOFTEST

# Set permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Pre-generate Eclipse project metadata so it appears as a project
# (This avoids the agent having to run "Import Maven Project" wizard which is complex to automate reliably if not pre-configured)
echo "Generating Eclipse metadata..."
su - ga -c "cd '$WORKSPACE_DIR' && mvn eclipse:eclipse -DdownloadSources=true -DdownloadJavadocs=true -q"

# Wait for Eclipse to be ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Ensure Eclipse is focused
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Project created at $WORKSPACE_DIR"
echo "Eclipse metadata generated. Agent can Import > Existing Projects into Workspace or just open it."