#!/bin/bash
set -e
echo "=== Setting up task: create_customer_journey_map ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists and is clean of any prior task artifacts
mkdir -p /home/ga/Diagrams
rm -f /home/ga/Diagrams/customer_journey_map.eddx 2>/dev/null || true
rm -f /home/ga/Diagrams/customer_journey_map.png 2>/dev/null || true
chown -R ga:ga /home/ga/Diagrams

# Kill any existing EdrawMax instances for a clean start
kill_edrawmax

# Launch EdrawMax fresh (no file argument — agent starts from home screen)
echo "Launching EdrawMax..."
launch_edrawmax
wait_for_edrawmax 90

# Allow full UI render time (EdrawMax is a heavy Qt/Chromium app)
sleep 15

# Dismiss login/recovery dialogs
dismiss_edrawmax_dialogs

# Maximize the EdrawMax window
maximize_edrawmax

# Focus the window
DISPLAY=:1 wmctrl -a "EdrawMax" 2>/dev/null || \
DISPLAY=:1 wmctrl -a "Wondershare EdrawMax" 2>/dev/null || true

# Take screenshot of initial state for evidence
take_screenshot /tmp/task_initial_state.png
echo "Initial state screenshot saved to /tmp/task_initial_state.png"

echo "=== Task setup complete ==="