#!/bin/bash
set -e
echo "=== Setting up Calendar Skills Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /home/ga/Documents/calendar_log.txt
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Ensure GCompris is closed before starting
kill_gcompris

# Launch GCompris at the main menu
# We do NOT navigate to the specific activity; the agent must find it.
echo "Launching GCompris..."
launch_gcompris

# Maximize the window for better VLM visibility
maximize_gcompris

# Verify GCompris is running
if ! pgrep -f "gcompris" > /dev/null; then
    echo "ERROR: GCompris failed to start"
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="