#!/bin/bash
echo "=== Setting up create_maven_project task ==="

# Ensure IntelliJ is running
source /workspace/scripts/task_utils.sh

# Make sure project directory doesn't already exist
rm -rf /home/ga/IdeaProjects/gs-maven 2>/dev/null || true

# Wait for IntelliJ to be ready (Welcome screen or project window)
wait_for_intellij 60 || echo "WARNING: IntelliJ not detected"

# Dismiss any dialogs that might appear
dismiss_dialogs 3

# Focus and maximize IntelliJ window
focus_intellij_window

# Additional stabilization wait
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
