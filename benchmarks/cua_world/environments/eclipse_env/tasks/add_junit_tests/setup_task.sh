#!/bin/bash
echo "=== Setting up add_junit_tests task ==="

source /workspace/scripts/task_utils.sh

# Copy the calculator project to workspace
rm -rf /home/ga/eclipse-workspace/calculator 2>/dev/null || true
cp -r /workspace/data/calculator /home/ga/eclipse-workspace/calculator
chown -R ga:ga /home/ga/eclipse-workspace/calculator

# Ensure test directory exists (but without test files)
mkdir -p /home/ga/eclipse-workspace/calculator/src/test/java/com/example/calculator
chown -R ga:ga /home/ga/eclipse-workspace/calculator/src/test

# Create Eclipse metadata files
cat > /home/ga/eclipse-workspace/calculator/.project << 'EOFPROJECT'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>calculator</name>
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

cat > /home/ga/eclipse-workspace/calculator/.classpath << 'EOFCLASSPATH'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java"/>
    <classpathentry kind="src" output="target/test-classes" path="src/test/java"/>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER"/>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
EOFCLASSPATH

chown -R ga:ga /home/ga/eclipse-workspace/calculator

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
echo "Calculator project files are at ~/eclipse-workspace/calculator/"
echo "The agent needs to import the Maven project into Eclipse first."
