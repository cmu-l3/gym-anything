#!/bin/bash
set -e
echo "=== Setting up scale_balance_activity task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure GCompris configuration is clean (reset to defaults but keep windowed mode)
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

# Kill any existing instances to ensure fresh start
kill_gcompris

# Launch GCompris at the main menu
# This uses the utility function which handles the display export and waiting
launch_gcompris

# Wait for window and maximize
sleep 2
maximize_gcompris
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Verify initial state
if [ -f /tmp/task_initial.png ]; then
    echo "Initial state captured successfully."
else
    echo "WARNING: Failed to capture initial state."
fi

echo "=== Task setup complete ==="
echo "GCompris launched at main menu."
echo "Agent must navigate to Scales Board activity and complete 3 levels."