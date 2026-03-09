#!/bin/bash
echo "=== Setting up difficulty_accommodation_config task ==="

source /workspace/scripts/task_utils.sh

# Remove any stale report file BEFORE recording timestamp
rm -f /home/ga/Desktop/accommodation_plan.txt

# Reset GCompris config to default (filterLevelMax=6) so we can detect changes
# This ensures a clean baseline
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

# Record task start timestamp AFTER cleanup
date +%s > /tmp/task_start_ts_difficulty_config

# Kill any running GCompris
kill_gcompris

# Launch GCompris at main menu
launch_gcompris
sleep 3
maximize_gcompris
sleep 2

take_screenshot /tmp/difficulty_config_start.png

echo "=== Setup complete. GCompris is at main menu with default settings (filterLevelMax=6). ==="
echo "Agent must:"
echo "  1. Access GCompris settings and change difficulty filter max to 3 or lower"
echo "  2. Navigate Math and Language categories to see accessible activities"
echo "  3. Complete at least 2 accessible activities"
echo "  4. Write accommodation plan to ~/Desktop/accommodation_plan.txt"
