#!/bin/bash
set -e
echo "=== Setting up target_score task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -f /tmp/target_final.png
rm -f /tmp/task_result.json

# Kill any existing GCompris instance
kill_gcompris

# Reset GCompris progress data so the target activity starts fresh
# This ensures level 1 is always the start
rm -rf /home/ga/.local/share/GCompris/gcompris-qt/ 2>/dev/null || true
mkdir -p /home/ga/.local/share/GCompris/gcompris-qt
chown -R ga:ga /home/ga/.local/share/GCompris

# Ensure config is set (no fullscreen, no audio, not first run)
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
launch_gcompris

# Maximize window for best visibility
maximize_gcompris

# Dismiss any startup dialogs if they appear
sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== target_score task setup complete ==="