#!/bin/bash
set -e
echo "=== Setting up Double Entry Table task ==="

# Source utilities for GCompris management
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/double_entry_success.png
rm -f /tmp/task_result.json

# Ensure GCompris is closed before starting
kill_gcompris

# Launch GCompris
# We launch it at the main menu so the agent must demonstrate navigation
echo "Launching GCompris..."
launch_gcompris

# Maximize the window to ensure icons are visible and interactions are consistent
maximize_gcompris

# Focus the window explicitly
DISPLAY=:1 wmctrl -a "GCompris" 2>/dev/null || true

# Take an initial screenshot to prove the clean starting state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="