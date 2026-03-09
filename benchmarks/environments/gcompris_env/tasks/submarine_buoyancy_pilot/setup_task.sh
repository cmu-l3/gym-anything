#!/bin/bash
set -e
echo "=== Setting up Submarine Buoyancy Pilot task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# clean up previous artifacts
rm -f /home/ga/Documents/submarine_depth.png
rm -f /home/ga/Documents/submarine_surface.png
rm -f /home/ga/Documents/captains_log.txt

# Ensure GCompris config is clean (no first-run dialogs)
mkdir -p /home/ga/.config/gcompris-qt
cat > /home/ga/.config/gcompris-qt/gcompris-qt.conf << 'EOF'
[General]
fullscreen=false
isFirstRun=false
enableAudio=false
EOF
chown -R ga:ga /home/ga/.config

# Kill any existing instances
kill_gcompris

# Launch GCompris
echo "Launching GCompris..."
launch_gcompris
sleep 2

# Maximize window
maximize_gcompris

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="