#!/bin/bash
set -e

echo "=== Setting up create_ant_build task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="commons-cli"
WORKSPACE_DIR="/home/ga/eclipse-workspace"
PROJECT_DIR="$WORKSPACE_DIR/$PROJECT_NAME"

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 1. Prepare Project Directory
echo "Cleaning previous project artifacts..."
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/src/main/java"

# 2. Download Real Data (Apache Commons CLI 1.6.0 Source)
echo "Downloading Apache Commons CLI sources..."
# We use the sources jar from Maven Central
SOURCE_URL="https://repo1.maven.org/maven2/commons-cli/commons-cli/1.6.0/commons-cli-1.6.0-sources.jar"
wget -q -O /tmp/commons-cli-sources.jar "$SOURCE_URL"

# Extract sources to src/main/java
# The sources jar contains the package directory structure (org/apache/...)
unzip -q /tmp/commons-cli-sources.jar -d "$PROJECT_DIR/src/main/java/"
rm -f /tmp/commons-cli-sources.jar
# Remove META-INF from source root if it exists
rm -rf "$PROJECT_DIR/src/main/java/META-INF"

# 3. Create Eclipse Project Metadata (.project and .classpath)
# This ensures Eclipse recognizes it as a Java project immediately
echo "Creating Eclipse project metadata..."

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
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
    </natures>
</projectDescription>
EOF

cat > "$PROJECT_DIR/.classpath" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" path="src/main/java"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17"/>
    <classpathentry kind="output" path="bin"/>
</classpath>
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# 4. Restart/Refresh Eclipse to load the project
# Since Eclipse might be running from the environment startup, we need to ensure it sees the new project.
# The most reliable way is to kill and restart it, or if it's not running, start it.
echo "Restarting Eclipse to load project..."
pkill -f eclipse || true
sleep 2

# Start Eclipse in background
su - ga -c "DISPLAY=:1 nohup /opt/eclipse/eclipse -data $WORKSPACE_DIR > /tmp/eclipse_task.log 2>&1 &"

# Wait for Eclipse to load
wait_for_eclipse 60 || echo "WARNING: Eclipse took too long to start"

# Focus and maximize
focus_eclipse_window
sleep 3

# Dismiss dialogs
dismiss_dialogs 3
close_welcome_tab

# Record initial state
echo "Creating initial state evidence..."
ls -R "$PROJECT_DIR" > /tmp/initial_file_structure.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="