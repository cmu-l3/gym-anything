#!/bin/bash
set -e
echo "=== Setting up Redraw Grid Pattern task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/redraw_complete.png
rm -f /tmp/task_result.json

# Kill any existing GCompris instances
kill_gcompris

# Ensure GCompris config is set for a clean environment
# We disable audio and set level range to ensure Level 1 is available
mkdir -p /home/ga/.config/gcompris-qt
cat > /home/ga/.config/gcompris-qt/gcompris-qt.conf << 'EOF'
[General]
fullscreen=false
isFirstRun=false
enableAudio=false
showLockAtStart=false
filterLevelMin=1
filterLevelMax=6
EOF
chown -R ga:ga /home/ga/.config/gcompris-qt

# Launch GCompris at the main menu
# We launch it as the 'ga' user
echo "Launching GCompris..."
launch_gcompris

# Maximize the window to ensure clear visibility for the agent and VLM
maximize_gcompris

# Dismiss any potential startup dialogs
sleep 1
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true

# Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Instructions for Agent:"
echo "1. Navigate to Discovery > Art category"
echo "2. Find 'Redraw the given image' activity"
echo "3. Complete Level 1 by matching the grid pattern"
echo "4. Save screenshot to /home/ga/redraw_complete.png"