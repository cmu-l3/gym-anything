#!/bin/bash
echo "=== Setting up create_maven_project task ==="

# Ensure Eclipse is running
source /workspace/scripts/task_utils.sh

# Make sure project directory doesn't already exist
rm -rf /home/ga/eclipse-workspace/gs-maven 2>/dev/null || true

# ANTI-CHEATING: Remove the sample data that could be copied
# The agent must CREATE the project, not copy it from /workspace/data/
echo "Removing sample data to prevent copying..."
rm -rf /workspace/data/gs-maven 2>/dev/null || true
rm -rf /workspace/data/gs-maven-broken 2>/dev/null || true

# Also remove any other potential sources of pre-made code
find /workspace -name "HelloWorld.java" -delete 2>/dev/null || true
find /workspace -name "Greeter.java" -delete 2>/dev/null || true

# Wait for Eclipse to be ready (Welcome screen or project window)
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected"

# Dismiss any dialogs that might appear
dismiss_dialogs 3

# Close welcome tab if present
close_welcome_tab

# Focus and maximize Eclipse window
focus_eclipse_window

# Additional stabilization wait
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "NOTE: Sample data has been removed - project must be created from scratch."
