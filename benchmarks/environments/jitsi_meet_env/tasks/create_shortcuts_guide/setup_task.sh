#!/bin/bash
set -e
echo "=== Setting up Create Shortcuts Guide task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/shortcuts_reference.txt
rm -f /home/ga/shortcuts_evidence.png
rm -f /tmp/task_result.json

# Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Start Firefox at the Jitsi landing page
# We do NOT join the meeting for the agent; they must do it.
echo "Starting Firefox..."
restart_firefox "${JITSI_BASE_URL:-http://localhost:8080}" 10

# Maximize Firefox to ensure UI elements are visible
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Instructions:"
echo "1. Join room 'TrainingSession' as 'Training Lead'"
echo "2. Open Keyboard Shortcuts overlay"
echo "3. Screenshot overlay to /home/ga/shortcuts_evidence.png"
echo "4. Write shortcuts for Mute, Camera, Filmstrip to /home/ga/shortcuts_reference.txt"