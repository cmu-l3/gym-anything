#!/bin/bash
set -e
echo "=== Setting up IALA Region B Channel Setup Task ==="

# Define paths
BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/w) Miami IALA B Approach"

# 1. Ensure Bridge Command is installed
if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found at $BC_BIN"
    exit 1
fi

# 2. Clean previous run artifacts
echo "Cleaning up previous scenarios..."
rm -rf "$SCENARIO_DIR"
rm -f /home/ga/Documents/channel_configuration_plan.txt
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch Bridge Command (Warm-up / Visibility)
# We launch it so the agent sees the application they are targeting,
# even though this task involves file editing.
echo "Launching Bridge Command..."
pkill -f "bridgecommand" 2>/dev/null || true
sleep 1

# Run as ga user, cd to data dir first
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_startup.log 2>&1 &"

# Wait for window
echo "Waiting for Bridge Command window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Focus window
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true

# 5. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="