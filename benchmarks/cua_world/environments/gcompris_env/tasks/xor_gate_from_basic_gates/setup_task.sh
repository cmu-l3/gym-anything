#!/bin/bash
set -e
echo "=== Setting up XOR Gate from Basic Gates task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Clean up previous artifacts BEFORE recording timestamp
rm -f /home/ga/Documents/xor_circuit.png
rm -f /tmp/task_result.json

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Kill any existing GCompris instances
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

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GCompris is running at the main menu."
echo "Agent must navigate to Digital Electronics and build an XOR circuit."
