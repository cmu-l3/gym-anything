#!/bin/bash
set -e
echo "=== Setting up apply_team_patch task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
WORKSPACE="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE/RadiationTherapy"
SRC_DIR="$PROJECT_DIR/src/main/java/com/med/physics"
TEST_DIR="$PROJECT_DIR/src/test/java/com/med/physics"
PATCH_FILE="/home/ga/Desktop/physics_fix.patch"

# Cleanup previous runs
rm -rf "$PROJECT_DIR"
rm -f "$PATCH_FILE"

# Create project structure
mkdir -p "$SRC_DIR"
mkdir -p "$TEST_DIR"
mkdir -p "$PROJECT_DIR/target"

# 1. Create POM
cat > "$PROJECT_DIR/pom.xml" << 'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.med</groupId>
    <artifactId>radiation-therapy</artifactId>
    <version>1.0.0</version>
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

# 2. Create Eclipse Project Metadata (.project)
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>RadiationTherapy</name>
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

# 3. Create Eclipse Classpath (.classpath)
cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java"/>
    <classpathentry kind="src" output="target/test-classes" path="src/test/java"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER"/>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
EOF

# 4. Create Initial (Buggy) Source Files

# CalibrationConstants.java (Old value 1.020)
cat > "$SRC_DIR/CalibrationConstants.java" << 'EOF'
package com.med.physics;

/**
 * Daily calibration factors for Linear Accelerator (Linac).
 */
public class CalibrationConstants {
    // Last calibrated: 2023-01-10
    public static final double LINEAR_ACCELERATOR_FACTOR = 1.020;
    public static final double TRAY_FACTOR = 0.985;
}
EOF

# DoseCalculator.java (Missing Inverse Square Law)
cat > "$SRC_DIR/DoseCalculator.java" << 'EOF'
package com.med.physics;

public class DoseCalculator {
    
    /**
     * Calculates Monitor Units (MU) required for a specific dose.
     * @param prescriptionDose Dose in cGy
     * @param distanceSourceToTumor Distance in cm (SSD)
     * @return Calculated Monitor Units
     */
    public double calculateMonitorUnits(double prescriptionDose, double distanceSourceToTumor) {
        // BUG: Formula assumes standard 100cm distance, ignores inverse square law for other distances
        double calibration = CalibrationConstants.LINEAR_ACCELERATOR_FACTOR;
        
        // Simple calculation: Dose / (Calibration * Tray)
        return prescriptionDose / (calibration * CalibrationConstants.TRAY_FACTOR);
    }
}
EOF

# 5. Create Test File (Fails with current code)
cat > "$TEST_DIR/DoseTest.java" << 'EOF'
package com.med.physics;

import static org.junit.Assert.*;
import org.junit.Test;

public class DoseTest {

    @Test
    public void testMonitorUnitCalculation() {
        DoseCalculator calc = new DoseCalculator();
        double dose = 200.0; // cGy
        double dist = 110.0; // cm (Extended SSD)
        
        // Expected Calculation with Patch:
        // Calibration = 1.035
        // Tray = 0.985
        // ISF = (110/100)^2 = 1.21
        // MU = (200 * 1.21) / (1.035 * 0.985) = 242.0 / 1.019475 = ~237.377
        
        // The buggy code returns:
        // MU = 200 / (1.020 * 0.985) = ~199.06 (ignoring ISF and using old factor)
        
        double result = calc.calculateMonitorUnits(dose, dist);
        
        // We expect the corrected value ~237.377 with tolerance 0.1
        assertEquals("Monitor Unit calculation incorrect - check Inverse Square Law and constants", 
                     237.377, result, 0.1);
    }
}
EOF

# 6. Generate the Patch File
# We create temporary "fixed" files to generate the diff
TEMP_FIXED="/tmp/fixed_src"
mkdir -p "$TEMP_FIXED/com/med/physics"

# Fixed Constants (1.035)
cat > "$TEMP_FIXED/com/med/physics/CalibrationConstants.java" << 'EOF'
package com.med.physics;

/**
 * Daily calibration factors for Linear Accelerator (Linac).
 */
public class CalibrationConstants {
    // Last calibrated: 2023-10-25
    public static final double LINEAR_ACCELERATOR_FACTOR = 1.035;
    public static final double TRAY_FACTOR = 0.985;
}
EOF

# Fixed Calculator (With Inverse Square Law)
cat > "$TEMP_FIXED/com/med/physics/DoseCalculator.java" << 'EOF'
package com.med.physics;

public class DoseCalculator {
    
    /**
     * Calculates Monitor Units (MU) required for a specific dose.
     * @param prescriptionDose Dose in cGy
     * @param distanceSourceToTumor Distance in cm (SSD)
     * @return Calculated Monitor Units
     */
    public double calculateMonitorUnits(double prescriptionDose, double distanceSourceToTumor) {
        double calibration = CalibrationConstants.LINEAR_ACCELERATOR_FACTOR;
        
        // Inverse Square Law Correction: (SSD / 100)^2
        double isf = Math.pow(distanceSourceToTumor / 100.0, 2);
        
        // Corrected Formula: Dose * ISF / (Calibration * Tray)
        return (prescriptionDose * isf) / (calibration * CalibrationConstants.TRAY_FACTOR);
    }
}
EOF

# Create the patch relative to project root so Eclipse "Apply Patch" works easily
cd "$PROJECT_DIR"
diff -u "src/main/java/com/med/physics/CalibrationConstants.java" "$TEMP_FIXED/com/med/physics/CalibrationConstants.java" > "$PATCH_FILE" || true
diff -u "src/main/java/com/med/physics/DoseCalculator.java" "$TEMP_FIXED/com/med/physics/DoseCalculator.java" >> "$PATCH_FILE" || true

# Cleanup temp files
rm -rf "$TEMP_FIXED"

# Set permissions
chown -R ga:ga "$WORKSPACE"
chown ga:ga "$PATCH_FILE"

# Wait for Eclipse to be ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Dismiss any dialogs
dismiss_dialogs 3

# Close welcome tab if present
close_welcome_tab

# Focus and maximize Eclipse window
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Project 'RadiationTherapy' created in workspace."
echo "Patch file located at $PATCH_FILE"