#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Hangman Game Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any previous result screenshot to prevent false positives
rm -f /home/ga/hangman_result.png

# Kill any existing GCompris instances to ensure clean state
kill_gcompris

# Launch GCompris at the main menu
# Note: task_utils.sh handles the launch details (sudo -u ga, DISPLAY=:1, etc.)
launch_gcompris

# Maximize the window for better visibility
maximize_gcompris

# Dismiss any startup dialogs/profile selectors if they appear
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state (Main Menu)
take_screenshot /tmp/task_initial_state.png

echo "=== Hangman Game Task setup complete ==="
echo "GCompris is running at the main menu."
echo "Agent goal: Navigate to Reading -> Hangman, play a round, screenshot result to ~/hangman_result.png"