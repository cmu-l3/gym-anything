#!/bin/bash
set -e
echo "=== Setting up Configure Save Actions task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define workspace paths
WORKSPACE="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE/LegacyCodebase"
SRC_DIR="$PROJECT_DIR/src/main/java/com/legacy"
SETTINGS_DIR="$PROJECT_DIR/.settings"

# 1. Clean up any previous run
rm -rf "$PROJECT_DIR"
mkdir -p "$SRC_DIR"
mkdir -p "$SETTINGS_DIR"

# 2. Create Eclipse .project file
cat > "$PROJECT_DIR/.project" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>LegacyCodebase</name>
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
XML

# 3. Create .classpath file
cat > "$PROJECT_DIR/.classpath" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" path="src/main/java"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
    <classpathentry kind="output" path="bin"/>
</classpath>
XML

# 4. Create JDT Core preferences (Compiler settings)
cat > "$SETTINGS_DIR/org.eclipse.jdt.core.prefs" << 'PREFS'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.inlineJsrBytecode=enabled
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.problem.assertIdentifier=error
org.eclipse.jdt.core.compiler.problem.enumIdentifier=error
org.eclipse.jdt.core.compiler.source=17
PREFS

# 5. Create the "Messy" Java file
# - Bad indentation (1 space, 5 spaces)
# - Unused imports
# - Trailing whitespace (will be added via sed)
cat > "$SRC_DIR/MessyService.java" << 'JAVA'
package com.legacy;

import java.util.List;
import java.util.Vector;  // Unused import
import java.util.ArrayList;
import java.util.Date;

public class MessyService {

 private String serviceName = "Legacy";

    public void processData(List<String> data) {
     if(data==null){
    System.out.println("No data");
     } else {
           System.out.println("Processing " + data.size() + " items");
     }
    }

    public String getName() {
    return this.serviceName;
    }
}
JAVA

# Add trailing whitespace to line 10
sed -i '10s/$/    /' "$SRC_DIR/MessyService.java"

# Set permissions
chown -R ga:ga "$WORKSPACE"

# 6. Record timestamps
date +%s > /tmp/task_start_time.txt
stat -c %Y "$SRC_DIR/MessyService.java" > /tmp/initial_file_mtime.txt

# 7. Start/Restart Eclipse to ensure project is loaded
# If Eclipse is running, we kill it to force a reload of the workspace which picks up the new project
pkill -f eclipse 2>/dev/null || true
sleep 2

echo "Starting Eclipse..."
su - ga -c "DISPLAY=:1 /opt/eclipse/eclipse -data $WORKSPACE -nosplash > /tmp/eclipse.log 2>&1 &"

# Wait for Eclipse
wait_for_eclipse 120

# Maximize window
focus_eclipse_window

# Wait for workspace scan
sleep 5

# Open the messy file
echo "Opening MessyService.java..."
DISPLAY=:1 xdotool key ctrl+shift+r
sleep 1
DISPLAY=:1 xdotool type "MessyService"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="