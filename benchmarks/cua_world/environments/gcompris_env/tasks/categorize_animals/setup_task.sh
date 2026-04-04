#!/bin/bash
set -e
echo "=== Setting up Categorize Animals task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous state
echo "Cleaning up previous GCompris state..."
kill_gcompris

# Remove local share data to reset progress (GCompris-qt)
rm -rf /home/ga/.local/share/GCompris/ 2>/dev/null || true
rm -rf /home/ga/.local/share/gcompris-qt/ 2>/dev/null || true

# Reset config to known defaults (no fullscreen, no audio to prevent issues)
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

# 2. Launch GCompris
echo "Launching GCompris..."
launch_gcompris

# 3. Configure Window
echo "Configuring window..."
maximize_gcompris

# Ensure window is focused
DISPLAY=:1 wmctrl -a "GCompris" 2>/dev/null || true

# 4. Capture Initial State
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

# Verify setup
if ! pgrep -f "gcompris" > /dev/null; then
    echo "ERROR: GCompris failed to start"
    exit 1
fi

echo "=== Task setup complete ==="
echo "GCompris is open at the main menu."