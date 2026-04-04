#!/bin/bash
echo "=== Setting up organize_working_sets task ==="

source /workspace/scripts/task_utils.sh

WORKSPACE_DIR="/home/ga/eclipse-workspace"
mkdir -p "$WORKSPACE_DIR"

# Define projects to create
PROJECTS=("DoseEngine" "DoseUI" "DoseTests" "Legacy-Converter" "ThirdParty-Utils")

echo "Creating dummy projects..."

for PROJ in "${PROJECTS[@]}"; do
    PROJ_DIR="$WORKSPACE_DIR/$PROJ"
    mkdir -p "$PROJ_DIR/src"
    
    # Create .project file
    cat > "$PROJ_DIR/.project" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>$PROJ</name>
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

    # Create .classpath file
    cat > "$PROJ_DIR/.classpath" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOF

    # Create a dummy class so it looks real
    mkdir -p "$PROJ_DIR/src/com/example"
    CLASS_NAME=$(echo "$PROJ" | sed 's/-//g')
    cat > "$PROJ_DIR/src/com/example/${CLASS_NAME}Placeholder.java" << EOF
package com.example;
public class ${CLASS_NAME}Placeholder {
    // Placeholder class for $PROJ
}
EOF
done

# Set permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Reset working sets configuration to ensure clean state
# We remove the workingsets.xml if it exists so we start fresh
rm -f "$WORKSPACE_DIR/.metadata/.plugins/org.eclipse.ui.workbench/workingsets.xml" 2>/dev/null || true

# Wait for Eclipse
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Focus and maximize
focus_eclipse_window
sleep 2

# Dismiss welcome/tips
dismiss_dialogs 3
close_welcome_tab

# Force Package Explorer to show (in case it's closed)
# Alt+Shift+Q, P is the shortcut, or we can rely on default perspective
# We'll assume default Java perspective which has Package Explorer

# Take initial screenshot
take_screenshot /tmp/task_start.png

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="
echo "Created 5 projects: ${PROJECTS[*]}"