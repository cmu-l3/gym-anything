#!/bin/bash
set -e
echo "=== Setting up algebra_addition task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous report file (clean state)
rm -f /home/ga/Documents/addition_report.txt

# Kill any existing GCompris instances
kill_gcompris

# Ensure GCompris config is set for windowed mode, no audio, not first run
# This ensures a consistent environment for the agent
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

# Launch GCompris at main menu
echo "Launching GCompris..."
launch_gcompris

# Maximize GCompris window for visibility
maximize_gcompris

# Dismiss any startup dialogs if they appear
sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== algebra_addition task setup complete ==="
echo "GCompris is running at the main menu."