#!/bin/bash
set -e
echo "=== Setting up Braille Alphabet task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Kill any existing GCompris instance
kill_gcompris

# Ensure GCompris config suppresses dialogs and starts windowed
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

# Clear any previous progress data so we can detect new activity.
# GCompris-qt stores data in ~/.local/share/GCompris/
rm -rf /home/ga/.local/share/GCompris/ 2>/dev/null || true
mkdir -p /home/ga/.local/share/GCompris
chown -R ga:ga /home/ga/.local/share/GCompris

# Launch GCompris at main menu
echo "Launching GCompris..."
launch_gcompris
sleep 5

# Maximize window for visibility
maximize_gcompris
sleep 2

# Dismiss any startup popups/dialogs if they appear
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Braille Alphabet task setup complete ==="