#!/bin/bash
set -euo pipefail

echo "=== Setting up enable_push_to_talk task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous evidence files to ensure freshness
rm -f /home/ga/ptt_settings.png
rm -f /home/ga/ptt_inactive.png
rm -f /home/ga/ptt_active.png
rm -f /tmp/task_result.json

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Start Firefox at Jitsi home page
# We do NOT join the room automatically; the agent must do it to find the settings
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Join room 'NoisyCafe', enable Push-to-Talk, and capture evidence screenshots."