#!/bin/bash
echo "=== Setting up fix_build_errors task ==="

source /workspace/scripts/task_utils.sh

# Copy the broken project to workspace
rm -rf /home/ga/eclipse-workspace/gs-maven-broken 2>/dev/null || true
cp -r /workspace/data/gs-maven-broken /home/ga/eclipse-workspace/gs-maven-broken
chown -R ga:ga /home/ga/eclipse-workspace/gs-maven-broken

# ANTI-CHEATING: Remove the working gs-maven project to prevent copying the solution
# The agent must FIX the broken project, not copy from a working one
rm -rf /workspace/data/gs-maven 2>/dev/null || true

# Create Eclipse .project file
cat > /home/ga/eclipse-workspace/gs-maven-broken/.project << 'EOFPROJECT'
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
    <name>gs-maven-broken</name>
    <comment></comment>
    <projects>
    </projects>
    <buildSpec>
        <buildCommand>
            <name>org.eclipse.jdt.core.javabuilder</name>
            <arguments>
            </arguments>
        </buildCommand>
        <buildCommand>
            <name>org.eclipse.m2e.core.maven2Builder</name>
            <arguments>
            </arguments>
        </buildCommand>
    </buildSpec>
    <natures>
        <nature>org.eclipse.jdt.core.javanature</nature>
        <nature>org.eclipse.m2e.core.maven2Nature</nature>
    </natures>
</projectDescription>
EOFPROJECT

# Create Eclipse .classpath file
cat > /home/ga/eclipse-workspace/gs-maven-broken/.classpath << 'EOFCLASSPATH'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
    <classpathentry kind="src" output="target/classes" path="src/main/java">
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
EOFCLASSPATH

# Create .settings directory with Maven prefs
mkdir -p /home/ga/eclipse-workspace/gs-maven-broken/.settings
cat > /home/ga/eclipse-workspace/gs-maven-broken/.settings/org.eclipse.jdt.core.prefs << 'EOFJDT'
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.targetPlatform=17
org.eclipse.jdt.core.compiler.compliance=17
org.eclipse.jdt.core.compiler.problem.forbiddenReference=warning
org.eclipse.jdt.core.compiler.source=17
EOFJDT

cat > /home/ga/eclipse-workspace/gs-maven-broken/.settings/org.eclipse.m2e.core.prefs << 'EOFM2E'
activeProfiles=
eclipse.preferences.version=1
resolveWorkspaceProjects=true
version=1
EOFM2E

chown -R ga:ga /home/ga/eclipse-workspace/gs-maven-broken

# Wait for Eclipse to be ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Dismiss any dialogs
dismiss_dialogs 3

# Close welcome tab if present
close_welcome_tab

# Focus and maximize Eclipse window
focus_eclipse_window
sleep 2

# Take initial screenshot showing Eclipse ready for import
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Project files are at ~/eclipse-workspace/gs-maven-broken/"
echo "The agent needs to import the Maven project into Eclipse to see the build errors."
echo "Import via: File > Import > Existing Maven Projects > select the directory"
