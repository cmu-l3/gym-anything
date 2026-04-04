#!/bin/bash
set -e
echo "=== Setting up analog_electricity_circuit task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean up any previous artifacts
rm -f /home/ga/circuit_complete.png
rm -f /tmp/task_result.json

# Kill any existing GCompris instance
kill_gcompris

# Ensure config suppresses dialogs and disables audio
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
chown ga:ga /home/ga/.config/gcompris-qt/gcompris-qt.conf

# Launch GCompris at main menu
echo "Launching GCompris..."
launch_gcompris
sleep 3

# Maximize the window
maximize_gcompris

# Dismiss any unexpected dialogs
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== analog_electricity_circuit task setup complete ==="