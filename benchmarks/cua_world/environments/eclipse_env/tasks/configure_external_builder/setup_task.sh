#!/bin/bash
echo "=== Setting up Configure External Builder Task ==="

source /workspace/scripts/task_utils.sh

# Define paths
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_NAME="AutoVer"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# Record start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous runs
rm -rf "$PROJECT_DIR" 2>/dev/null || true

# Create project structure
echo "Creating project structure..."
mkdir -p "$PROJECT_DIR/src/main/java/com/example"
mkdir -p "$PROJECT_DIR/src/main/resources"
mkdir -p "$PROJECT_DIR/scripts"
mkdir -p "$PROJECT_DIR/bin"

# Create .project file (Standard Java Project)
cat > "$PROJECT_DIR/.project" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>AutoVer</name>
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

# Create .classpath file
cat > "$PROJECT_DIR/.classpath" << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src/main/java"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
	<classpathentry kind="output" path="bin"/>
</classpath>
XML

# Create dummy Java file
cat > "$PROJECT_DIR/src/main/java/com/example/App.java" << 'JAVA'
package com.example;

public class App {
    public static void main(String[] args) {
        System.out.println("AutoVer Application - Version Manager");
    }
}
JAVA

# Create the generation script
# We add a sleep to ensure the timestamp is distinct during execution
cat > "$PROJECT_DIR/scripts/gen_version.sh" << 'BASH'
#!/bin/bash
# Simulates a version generator
echo "Generating version info..."
TARGET_DIR="$(dirname "$0")/../src/main/resources"
mkdir -p "$TARGET_DIR"
# Write timestamp
date +%s > "$TARGET_DIR/version.txt"
echo "Generated version.txt at $(date)"
BASH

# Make script executable
chmod +x "$PROJECT_DIR/scripts/gen_version.sh"

# Fix ownership
chown -R ga:ga "$PROJECT_DIR"

# Wait for Eclipse to be ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Maximize Eclipse
focus_eclipse_window
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Project created at $PROJECT_DIR"