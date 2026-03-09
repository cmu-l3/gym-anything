#!/bin/bash
echo "=== Setting up enforce_strict_compiler_settings task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

PROJECT_NAME="RadiationPlanningCore"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# 1. Clean up any previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true

# 2. Create Project Structure
mkdir -p "$PROJECT_DIR/src/com/med/radiation"
mkdir -p "$PROJECT_DIR/.settings"
mkdir -p "$PROJECT_DIR/bin"

# 3. Create .project file
cat > "$PROJECT_DIR/.project" <<EOF
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
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
	</natures>
</projectDescription>
EOF

# 4. Create .classpath file
cat > "$PROJECT_DIR/.classpath" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/java-17-openjdk-amd64"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOF

# 5. Create initial (default) JDT prefs
# We deliberately do NOT set the specific error keys here, or set them to warning/ignore
cat > "$PROJECT_DIR/.settings/org.eclipse.jdt.core.prefs" <<EOF
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.source=17
org.eclipse.jdt.core.compiler.problem.resourceLeak=warning
org.eclipse.jdt.core.compiler.problem.potentialNullReference=warning
EOF

# 6. Create Java source file with intentional issues
cat > "$PROJECT_DIR/src/com/med/radiation/DosimetryCalculator.java" <<'JAVAEOF'
package com.med.radiation;

import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.util.Scanner;

/**
 * Calculates radiation dose distributions based on patient profiles.
 * Critical component for treatment planning.
 */
public class DosimetryCalculator {

    /**
     * Loads a patient profile from the filesystem.
     * WARNING: This method contains a resource leak!
     */
    public void loadPatientProfile(String profilePath) throws FileNotFoundException {
        System.out.println("Loading profile: " + profilePath);
        
        // RESOURCE LEAK: FileInputStream is never closed
        // This should be flagged by Eclipse as a warning (default) or error (goal)
        FileInputStream fis = new FileInputStream(profilePath);
        Scanner scanner = new Scanner(fis);
        
        while (scanner.hasNextLine()) {
            String data = scanner.nextLine();
            System.out.println("Processing: " + data);
        }
        // Missing fis.close() or try-with-resources
    }

    /**
     * Calculates the dose for a given configuration.
     * WARNING: This method has potential null pointer access!
     */
    public double calculateDose(Double overrideFactor) {
        if (overrideFactor == null) {
            System.out.println("No override factor provided.");
        }
        
        // POTENTIAL NULL POINTER ACCESS: overrideFactor could be null here
        // if the if-block above executed but didn't return/throw.
        double factor = overrideFactor.doubleValue(); 
        
        return 10.0 * factor;
    }
}
JAVAEOF

# 7. Set ownership
chown -R ga:ga "$WORKSPACE_DIR"

# 8. Ensure Eclipse is ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Focus Eclipse
focus_eclipse_window
sleep 2

# Dismiss dialogs
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Project created at $PROJECT_DIR"