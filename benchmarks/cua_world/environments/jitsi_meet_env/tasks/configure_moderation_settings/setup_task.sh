#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up: Configure Moderation Settings ==="

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is running
echo "Checking Jitsi Meet availability..."
wait_for_http "$JITSI_BASE_URL" 120

# Stop any existing Firefox instances to ensure clean state
stop_firefox
sleep 2

# Start Firefox at the CompanyAllHands room pre-join page
# The agent will have to click "Join meeting"
echo "Starting Firefox at CompanyAllHands room..."
restart_firefox "${JITSI_BASE_URL}/CompanyAllHands" 12

# Maximize the Firefox window
maximize_firefox
sleep 3

# Focus Firefox
focus_firefox
sleep 2

# Dismiss any spurious dialogs (like "Allow notifications")
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state (should show pre-join screen)
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="
echo "Firefox should be on the pre-join screen for CompanyAllHands"
echo "Agent needs to: join meeting -> Settings -> Moderator tab -> enable 3 toggles"