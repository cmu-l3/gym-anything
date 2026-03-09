#!/bin/bash
set -e
echo "=== Setting up Attach Source Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
WORKSPACE="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE/TreatmentPlanner"
DOWNLOADS="/home/ga/Downloads"

# Clean previous run
rm -rf "$PROJECT_DIR"
rm -f "$DOWNLOADS/dose-engine-src.zip"
mkdir -p "$PROJECT_DIR/src/main/java/com/dosimetry/app"
mkdir -p "$PROJECT_DIR/lib"
mkdir -p "$DOWNLOADS"

# ------------------------------------------------------------------
# 1. Create the Library Source Code (The content we want to see)
# ------------------------------------------------------------------
echo "Generating library source..."
TMP_BUILD="/tmp/dose_build"
mkdir -p "$TMP_BUILD/com/dosimetry/engine"

cat > "$TMP_BUILD/com/dosimetry/engine/DoseCalculator.java" << 'EOF'
package com.dosimetry.engine;

/**
 * Legacy Dose Calculation Engine for Photon Beams.
 * PROPRIETARY AND CONFIDENTIAL.
 * 
 * Algorithm: Modified Clarkson Integration with TMR correction.
 */
public class DoseCalculator {
    
    private double calibrationFactor;
    private static final double PDD_REF_DEPTH = 10.0;

    public DoseCalculator(double calibrationFactor) {
        this.calibrationFactor = calibrationFactor;
    }

    /**
     * Calculates Monitor Units (MU) for a given prescription dose.
     * 
     * @param doseGy Target dose in Gray
     * @param outputFactor Field size output factor (Sc,p)
     * @param tmr Tissue Maximum Ratio at depth
     * @param wedgeFactor Wedge transmission factor (0.0 - 1.0)
     * @return Monitor Units required
     */
    public double calculateMonitorUnits(double doseGy, double outputFactor, double tmr, double wedgeFactor) {
        if (outputFactor <= 0 || tmr <= 0 || wedgeFactor <= 0) {
            throw new IllegalArgumentException("Dosimetric factors must be positive");
        }
        
        // FORMULA: MU = Dose / (Cal * Scp * TMR * WF * INV_SQ)
        // Assuming isocentric setup where inverse square is handled in TMR or separate factor
        
        double mu = doseGy / (calibrationFactor * outputFactor * tmr * wedgeFactor);
        return Math.round(mu * 100.0) / 100.0;
    }
    
    public String getVersion() {
        return "v1.4.2-LEGACY";
    }
}
EOF

# ------------------------------------------------------------------
# 2. Compile the Library and Create JAR
# ------------------------------------------------------------------
echo "Compiling library..."
javac -d "$TMP_BUILD" "$TMP_BUILD/com/dosimetry/engine/DoseCalculator.java"

echo "Creating binary JAR..."
# Create jar with only class files
jar -cf "$PROJECT_DIR/lib/dose-engine.jar" -C "$TMP_BUILD" com/dosimetry/engine/DoseCalculator.class

# ------------------------------------------------------------------
# 3. Create the Source ZIP
# ------------------------------------------------------------------
echo "Creating source ZIP..."
# Create zip with only java files
cd "$TMP_BUILD"
zip -r "$DOWNLOADS/dose-engine-src.zip" com/dosimetry/engine/DoseCalculator.java
cd - > /dev/null

# Clean build artifacts
rm -rf "$TMP_BUILD"

# ------------------------------------------------------------------
# 4. Create the Consumer Project Code
# ------------------------------------------------------------------
echo "Creating consumer app..."
cat > "$PROJECT_DIR/src/main/java/com/dosimetry/app/PlannerApp.java" << 'EOF'
package com.dosimetry.app;

import com.dosimetry.engine.DoseCalculator;

public class PlannerApp {
    public static void main(String[] args) {
        System.out.println("Initializing Treatment Planning System...");
        
        // Initialize engine with 1cGy/MU calibration
        DoseCalculator engine = new DoseCalculator(0.01);
        
        // Calculate for 200 cGy prescription
        // We need to inspect source to understand if ISL is included in this call
        double mu = engine.calculateMonitorUnits(2.0, 0.985, 0.892, 1.0);
        
        System.out.println("Required MU: " + mu);
        System.out.println("Engine Version: " + engine.getVersion());
    }
}
EOF

# ------------------------------------------------------------------
# 5. Create Eclipse Project Metadata
# ------------------------------------------------------------------
echo "Configuring Eclipse project..."

# .project file
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>TreatmentPlanner</name>
	<comment></comment>
	<projects>
	</projects>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.jdt.core.javabuilder</name>
			<arguments>
			</arguments>
		</buildCommand>
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
	</natures>
</projectDescription>
EOF

# .classpath file - CRITICAL: Must NOT have sourcepath initially
cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src/main/java"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/java-17-openjdk-amd64"/>
	<classpathentry kind="lib" path="lib/dose-engine.jar"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"
chown -R ga:ga "$DOWNLOADS"

# ------------------------------------------------------------------
# 6. Launch Eclipse
# ------------------------------------------------------------------
# Wait for Eclipse to be ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Focus and maximize
focus_eclipse_window
sleep 2

# Dismiss any dialogs
dismiss_dialogs 3
close_welcome_tab

# Force Eclipse to refresh/import the project if it was already open
# (If Eclipse was already running, it might not see the new files immediately)
# We can just rely on the agent to Open Project or Refresh, or we can restart Eclipse
# For robustness in this env, we assume Eclipse scans workspace on focus or startup.

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="