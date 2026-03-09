#!/bin/bash
echo "=== Setting up refactor_rename_class task ==="

source /workspace/scripts/task_utils.sh

# Copy the refactor-demo project to workspace
rm -rf /home/ga/eclipse-workspace/refactor-demo 2>/dev/null || true
cp -r /workspace/data/refactor-demo /home/ga/eclipse-workspace/refactor-demo
chown -R ga:ga /home/ga/eclipse-workspace/refactor-demo

# Create Eclipse metadata files
cat > /home/ga/eclipse-workspace/refactor-demo/.project << 'EOFPROJECT'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>refactor-demo</name>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
EOFPROJECT

cat > /home/ga/eclipse-workspace/refactor-demo/.classpath << 'EOFCLASSPATH'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER"/>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
EOFCLASSPATH

chown -R ga:ga /home/ga/eclipse-workspace/refactor-demo

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

echo "=== Task setup complete ==="
echo "Refactor-demo project files are at ~/eclipse-workspace/refactor-demo/"
echo "The agent needs to import the Maven project into Eclipse first."
