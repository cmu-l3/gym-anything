#!/bin/bash
set -e

echo "=== Setting up Geography Puzzle Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous task artifacts
rm -f /home/ga/geography_result.png
rm -f /tmp/task_initial_state.png
rm -f /tmp/task_result.json

# Kill any existing GCompris instance
kill_gcompris

# Ensure GCompris config exists and is properly set
# We set filter levels to ensure the geography activity is visible
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
echo "Launching GCompris..."
launch_gcompris

# Maximize the window for better visibility
sleep 2
maximize_gcompris

# Dismiss any startup dialogs if they appear
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

# Verify GCompris is visible
if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "gcompris"; then
    echo "GCompris is running and visible on main menu"
else
    echo "WARNING: GCompris window not detected"
fi

echo "=== Geography Puzzle Task setup complete ==="