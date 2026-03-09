#!/bin/bash
set -e
echo "=== Setting up raise_hand_speaker_stats task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Define meeting URL
MEETING_URL="${JITSI_BASE_URL:-http://localhost:8080}/InterpreterSession2024"

# Restart Firefox at the pre-join screen
# We do NOT join the meeting; the agent must do that
echo "Starting Firefox at $MEETING_URL..."
restart_firefox "$MEETING_URL" 10

# Maximize Firefox for consistent UI location
maximize_firefox
sleep 2

# Focus Firefox to ensure it receives input
focus_firefox
sleep 1

# Dismiss any potential popups (like translation offers)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Agent is at pre-join screen for InterpreterSession2024"