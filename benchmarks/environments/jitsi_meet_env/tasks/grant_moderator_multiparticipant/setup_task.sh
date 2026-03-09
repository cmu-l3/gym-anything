#!/bin/bash
set -euo pipefail

echo "=== Setting up grant_moderator_multiparticipant task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any previous result artifacts
rm -f /home/ga/moderator_granted.png
rm -f /tmp/task_result.json

# Verify Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Set up the initial state: Firefox open at the specific meeting URL
MEETING_URL="http://localhost:8080/virtual-fitness-class"
echo "Navigating to $MEETING_URL"

# Restart Firefox cleanly
restart_firefox "$MEETING_URL" 10
maximize_firefox
focus_firefox

# Wait a moment for the pre-join screen to fully load
sleep 5

# Capture initial state evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "You are on the pre-join screen for 'virtual-fitness-class'."
echo "Task: Join as 'FitnessCoach', open a new tab, join as 'ClassHelper', and grant moderator rights to ClassHelper."