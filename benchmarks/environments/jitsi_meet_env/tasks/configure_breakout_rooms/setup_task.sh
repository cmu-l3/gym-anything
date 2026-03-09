#!/bin/bash
set -e

echo "=== Setting up Configure Breakout Rooms task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous run artifacts
rm -f /home/ga/breakout_rooms_evidence.png
rm -f /tmp/task_result.json

# 3. Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# 4. Prepare Firefox
# Navigate to the specific meeting URL so agent starts at pre-join screen
MEETING_URL="http://localhost:8080/QuarterlyPlanning"

echo "Launching Firefox at $MEETING_URL..."
restart_firefox "$MEETING_URL" 12

# 5. Ensure window is maximized and focused
maximize_firefox
focus_firefox
sleep 2

# 6. Capture initial state screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot captured."

echo "=== Setup complete ==="
echo "Task: Join meeting, create 3 breakout rooms ('Revenue Strategy', 'Operations Review', 'Product Roadmap'), and save screenshot of panel to ~/breakout_rooms_evidence.png"