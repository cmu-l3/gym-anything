#!/bin/bash
set -e
echo "=== Setting up Super Brain task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any existing GCompris instances
kill_gcompris

# 1. Clean Configuration & Data
# We want Level 1 to start fresh, so we wipe progress.
echo "Cleaning GCompris configuration and progress..."
rm -rf /home/ga/.local/share/GCompris 2>/dev/null || true
mkdir -p /home/ga/.config/gcompris-qt

# Write config: Windowed mode (1280x720 usually good for agents), No Audio, No First Run
cat > /home/ga/.config/gcompris-qt/gcompris-qt.conf << 'EOF'
[General]
fullscreen=false
isFirstRun=false
enableAudio=false
showLockAtStart=false
filterLevelMin=1
filterLevelMax=6
EOF
chown -R ga:ga /home/ga/.config
chown -R ga:ga /home/ga/.local

# 2. Launch GCompris
echo "Launching GCompris..."
launch_gcompris

# 3. Maximize Window
# Critical for VLM visibility
maximize_gcompris

# 4. Initial State Screenshot
sleep 2
take_screenshot /tmp/task_initial.png

# 5. Verify App is Running
if ! pgrep -f "gcompris" > /dev/null; then
    echo "ERROR: GCompris failed to start."
    exit 1
fi

echo "=== Task setup complete ==="
echo "Agent starts at GCompris Main Menu."