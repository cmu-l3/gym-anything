#!/bin/bash
echo "=== Setting up export_session task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing Ardour instances
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"

# Ensure the export directory exists and is empty
su - ga -c "mkdir -p /home/ga/Audio/export"
rm -f /home/ga/Audio/export/*.wav 2>/dev/null || true

# Launch Ardour with the existing session
launch_ardour_session "$SESSION_DIR/MyProject.ardour"

sleep 3

echo "=== Task setup complete ==="
echo "Agent should export the session to /home/ga/Audio/export/ as WAV"
