#!/bin/bash
set -e
echo "=== Setting up configure_classroom task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing GCompris
kill_gcompris

# Define config directory
CONFIG_DIR="/home/ga/.config/gcompris-qt"
mkdir -p "$CONFIG_DIR"

# Reset config to known initial state (audio off, all levels, no virtual keyboard)
# This ensures the agent isn't starting with the task already done
cat > "$CONFIG_DIR/gcompris-qt.conf" << 'EOF'
[General]
fullscreen=false
isFirstRun=false
enableAudio=false
showLockAtStart=false
filterLevelMin=1
filterLevelMax=6
isVirtualKeyboard=false
EOF
chown -R ga:ga "$CONFIG_DIR"

# Also handle KDE path if GCompris uses that in this environment
KDE_CONFIG_DIR="/home/ga/.config/KDE"
mkdir -p "$KDE_CONFIG_DIR"
cp "$CONFIG_DIR/gcompris-qt.conf" "$KDE_CONFIG_DIR/gcompris-qt.conf" 2>/dev/null || true
chown -R ga:ga "$KDE_CONFIG_DIR"

# Save initial config content for comparison later
cp "$CONFIG_DIR/gcompris-qt.conf" /tmp/initial_gcompris_config.txt

# Launch GCompris at main menu
echo "Launching GCompris..."
launch_gcompris
maximize_gcompris

# Verify GCompris is running
if ! pgrep -f "gcompris" > /dev/null; then
    echo "ERROR: GCompris failed to start"
    exit 1
fi

# Take screenshot of initial state
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="