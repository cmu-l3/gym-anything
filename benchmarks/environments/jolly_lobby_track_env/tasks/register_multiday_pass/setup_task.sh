#!/bin/bash
set -e
echo "=== Setting up register_multiday_pass task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
date -I > /tmp/task_date.txt

# Ensure clean state for proof files
rm -f /home/ga/Documents/multiday_pass_proof.png
rm -f /home/ga/Documents/multiday_pass_info.txt

# Launch Lobby Track and wait for it to load
# This utility function (defined in environment scripts) handles 
# killing old instances, launching wine, and waiting for the window
launch_lobbytrack

# Ensure window is focused and maximized
WID=$(DISPLAY=:1 wmctrl -l | grep -i "lobby\|jolly\|track" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot for debug/evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Current Date: $(date)"
echo "Target Expiration Date (approx): $(date -d "+14 days")"