#!/bin/bash
set -e
echo "=== Setting up setup_linked_resources task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Setup External Data Directory (Simulated Network Drive)
EXTERNAL_DIR="/opt/hospital/protocols"
echo "Creating external data at $EXTERNAL_DIR..."
mkdir -p "$EXTERNAL_DIR"

# Create dummy protocol PDFs
touch "$EXTERNAL_DIR/Brain_SRS_Protocol_v3.0.pdf"
touch "$EXTERNAL_DIR/HeadNeck_IMRT_Protocol_v1.2.pdf"
touch "$EXTERNAL_DIR/Lung_SBRT_Protocol_v2.1.pdf"
touch "$EXTERNAL_DIR/Prostate_VMAT_Protocol_v4.5.pdf"

# Set permissions: Readable by everyone, Writable only by root (simulating read-only for user)
chmod -R 755 "$EXTERNAL_DIR"
chown -R root:root "$EXTERNAL_DIR"

# 2. Setup Eclipse Project 'TreatmentPlanner'
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/TreatmentPlanner"

echo "Creating TreatmentPlanner project..."
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/src"

# Create .project file
cat > "$PROJECT_DIR/.project" << 'EOFPROJECT'
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
EOFPROJECT

# Create .classpath file
cat > "$PROJECT_DIR/.classpath" << 'EOFCLASSPATH'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
EOFCLASSPATH

# Create package directory
mkdir -p "$PROJECT_DIR/src/com/hospital/planning"

# Set ownership
chown -R ga:ga "$WORKSPACE_DIR"

# 3. Launch Eclipse
echo "Launching Eclipse..."
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Dismiss dialogs
dismiss_dialogs 3
close_welcome_tab

# Import the project into the workspace (programmatically if possible, otherwise rely on auto-scan or user)
# Since we created it directly in the workspace folder, Eclipse might not see it until refreshed/imported.
# To make it easier, we will rely on the fact it's in the default workspace location.
# Often Eclipse needs a restart or import to see manually added folders.
# We'll trust the agent to "Open Project" or we can try to force it via existing metadata if Eclipse was closed.

# Focus window
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Project 'TreatmentPlanner' is prepared in ~/eclipse-workspace/"
echo "External data is located at /opt/hospital/protocols"