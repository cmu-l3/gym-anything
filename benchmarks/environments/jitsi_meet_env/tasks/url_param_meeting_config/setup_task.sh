#!/bin/bash
set -e
echo "=== Setting up Jitsi URL Param Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clear previous artifacts to ensure fresh run
rm -f /home/ga/meeting_url.txt
rm -f /home/ga/meeting_config_report.txt
rm -f /home/ga/meeting_configured.png
rm -f /tmp/task_result.json

# Ensure Jitsi is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Start Firefox at the landing page (clean state)
echo "Starting Firefox..."
restart_firefox "http://localhost:8080" 8
maximize_firefox
focus_firefox

# Dismiss any potential "Allow camera/mic" popups (though prefs usually handle this)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="