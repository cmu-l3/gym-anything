#!/bin/bash
set -e
echo "=== Setting up set_meeting_subject task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial window titles for comparison
DISPLAY=:1 wmctrl -l > /tmp/initial_windows.txt 2>/dev/null || true

# Ensure Jitsi Meet is accessible
wait_for_http "http://localhost:8080" 120

# Stop any existing Firefox instance to ensure clean state
stop_firefox

# Start Firefox at the WeeklySync room pre-join page
# The agent will need to click "Join"
restart_firefox "http://localhost:8080/WeeklySync" 10

# Maximize Firefox window for better visibility
maximize_firefox
sleep 3

# Dismiss any first-run dialogs or permission prompts if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

# Verify we're on the pre-join screen (or at least browser is open)
echo "Initial state: Firefox should be on the WeeklySync pre-join screen"
DISPLAY=:1 wmctrl -l

echo "=== Task setup complete ==="
echo "TASK: Join the meeting and set the subject to: Q4 2024 Quarterly Ops Review - Budget and Headcount"