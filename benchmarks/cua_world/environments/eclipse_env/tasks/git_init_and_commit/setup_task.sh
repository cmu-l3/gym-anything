#!/bin/bash
set -e
echo "=== Setting up git_init_and_commit task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/eclipse-workspace/commons-cli"

# 1. Clean up any previous state
echo "Cleaning workspace..."
rm -rf "$PROJECT_DIR"
rm -f /tmp/task_result.json

# 2. Prepare the project source code (Apache Commons CLI)
echo "Setting up project source..."
mkdir -p "$PROJECT_DIR"

# Download source code (using a stable tag to ensure consistency)
# We download a zip to avoid carrying over .git metadata
cd /tmp
wget -q -O commons-cli-src.zip https://github.com/apache/commons-cli/archive/refs/tags/rel/commons-cli-1.6.0.zip
unzip -q commons-cli-src.zip
# Move contents to project dir (strip root folder)
rsync -a commons-cli-rel-commons-cli-1.6.0/ "$PROJECT_DIR/"
rm -rf commons-cli-src.zip commons-cli-rel-commons-cli-1.6.0

# 3. Ensure NO git artifacts exist
rm -rf "$PROJECT_DIR/.git"
rm -f "$PROJECT_DIR/.gitignore"
rm -f "$PROJECT_DIR/.gitattributes"

# 4. Create Eclipse project metadata so it appears as a valid project
# (This avoids needing to go through the "Import" wizard in the UI)
echo "Creating Eclipse project metadata..."

# .project file
cat > "$PROJECT_DIR/.project" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>commons-cli</name>
    <comment></comment>
    <projects></projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments></arguments>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
            <arguments></arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
EOF

# .classpath file
cat > "$PROJECT_DIR/.classpath" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="src" output="target/test-classes" path="src/test/java">
        <attributes>
            <attribute name="optional" value="true"/>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-17">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="con" path="org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER">
        <attributes>
            <attribute name="maven.pomderived" value="true"/>
        </attributes>
    </classpathentry>
    <classpathentry kind="output" path="target/classes"/>
</classpath>
EOF

# Create target directory to simulate build artifacts (testing .gitignore)
mkdir -p "$PROJECT_DIR/target/classes"
touch "$PROJECT_DIR/target/classes/FakeClass.class"
touch "$PROJECT_DIR/target/maven-status"

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# 5. Launch Eclipse
echo "Starting Eclipse..."
# Check if already running
if ! pgrep -f "eclipse" > /dev/null; then
    su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 nohup /opt/eclipse/eclipse -data /home/ga/eclipse-workspace -nosplash > /tmp/eclipse_startup.log 2>&1 &"
else
    echo "Eclipse is already running, restarting to pick up new project..."
    pkill -f "eclipse"
    sleep 5
    su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 nohup /opt/eclipse/eclipse -data /home/ga/eclipse-workspace -nosplash > /tmp/eclipse_startup.log 2>&1 &"
fi

# Wait for Eclipse window
wait_for_eclipse 120

# Maximize and focus
focus_eclipse_window
sleep 3

# Dismiss dialogs
dismiss_dialogs 5
close_welcome_tab

# Ensure Package Explorer is visible (Window > Show View > Package Explorer)
# This is hard to do programmatically, but Eclipse remembers state.
# We trust the default perspective.

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Project ready at $PROJECT_DIR"
echo "Git status: No repository (as expected)"