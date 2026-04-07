#!/bin/bash
set -e
echo "=== Setting up JVM Runtime Forensics Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure JDK tools are on PATH (Critical for this task)
# The environment installs openjdk-17-jdk, so tools should be in /usr/lib/jvm/java-17-openjdk-amd64/bin
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH

# Verify tools exist
echo "Verifying JDK tools..."
REQUIRED_TOOLS="jps jstack jstat jcmd jmap"
for tool in $REQUIRED_TOOLS; do
    if ! command -v $tool &> /dev/null; then
        echo "WARNING: $tool not found in PATH. Linking from JAVA_HOME..."
        if [ -f "$JAVA_HOME/bin/$tool" ]; then
            ln -sf "$JAVA_HOME/bin/$tool" "/usr/local/bin/$tool"
        else
            echo "ERROR: $tool not found in JAVA_HOME either."
        fi
    fi
done

# Clean up any previous artifacts
rm -rf /home/ga/Desktop/jvm_forensics 2>/dev/null || true

# Ensure OpenICE is running
# This task requires a running JVM to analyze
echo "Ensuring OpenICE is running..."
ensure_openice_running

# Wait for OpenICE window to be sure it's fully up
if ! wait_for_window "openice|ice|supervisor|demo" 60; then
    echo "Warning: OpenICE window not detected, but process might be running."
fi

# Focus the window
focus_openice_window
sleep 1

# Capture the ACTUAL PID of the OpenICE application (hidden from agent)
# We filter for the process running the demo-apps, excluding the gradle daemon/wrapper if possible
ACTUAL_PID=$(jps -l | grep "demo-apps" | awk '{print $1}' | head -1)
echo "$ACTUAL_PID" > /tmp/ground_truth_pid.txt
echo "Ground Truth PID: $ACTUAL_PID"

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="