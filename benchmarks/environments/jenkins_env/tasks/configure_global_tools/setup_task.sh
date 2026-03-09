#!/bin/bash
# Setup script for Configure Global Tools task

echo "=== Setting up Configure Global Tools Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Jenkins API to be ready
echo "Waiting for Jenkins API..."
if ! wait_for_jenkins_api 120; then
    echo "ERROR: Jenkins API not ready"
    exit 1
fi

# Ensure Maven Integration plugin is installed
# This is required for the "Maven" section to appear in Global Tool Configuration
echo "Checking/Installing Maven Integration plugin..."
PLUGIN_LIST=$(jenkins_cli list-plugins)
if ! echo "$PLUGIN_LIST" | grep -q "maven-plugin"; then
    echo "Installing maven-plugin..."
    jenkins_cli install-plugin maven-plugin
    
    echo "Restarting Jenkins to apply plugin changes..."
    jenkins_cli safe-restart
    
    # Wait for restart
    sleep 15
    wait_for_jenkins_api 180
else
    echo "maven-plugin already installed."
fi

# Reset Global Tools to empty state (remove any existing JDKs or Mavens)
echo "Resetting tool configurations..."
cat > /tmp/reset_tools.groovy << 'GROOVY'
import jenkins.model.*
import hudson.model.*
import hudson.tasks.Maven.*

def inst = Jenkins.instance

// Clear JDKs
def jdkDesc = inst.getDescriptor("hudson.model.JDK")
jdkDesc.setInstallations()
jdkDesc.save()

// Clear Mavens
def mavenDesc = inst.getDescriptor("hudson.tasks.Maven$DescriptorImpl")
mavenDesc.setInstallations()
mavenDesc.save()

println "Tools reset complete"
GROOVY

# Execute reset script
curl -s -u "$JENKINS_USER:$JENKINS_PASS" --data-urlencode "script=$(cat /tmp/reset_tools.groovy)" "$JENKINS_URL/scriptText"

# Record initial state (should be empty)
echo "Recording initial state..."
curl -s -u "$JENKINS_USER:$JENKINS_PASS" --data-urlencode "script=$(cat /tmp/reset_tools.groovy)" "$JENKINS_URL/scriptText" > /tmp/initial_tool_state.txt

# Ensure Firefox is running and focused on Jenkins dashboard
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    DISPLAY=:1 firefox "$JENKINS_URL" > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|jenkins" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Configure Global Tools Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Go to Manage Jenkins > Tools"
echo "  2. Add JDK: Name='JDK-17', JAVA_HOME='/opt/java/openjdk' (Uncheck install automatically)"
echo "  3. Add Maven: Name='Maven-3.9.6', Version='3.9.6' (Check install automatically)"
echo "  4. Save"