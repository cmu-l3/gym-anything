#!/bin/bash
set -e
echo "=== Setting up Ferry Schedule Task ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_NAME="f) Southampton Ferry Schedule"
SCENARIO_DIR="$BC_DATA/Scenarios/$SCENARIO_NAME"

# Clean up any previous attempts to ensure fresh start
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing previous scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# Ensure Bridge Command directory exists
if [ ! -d "$BC_DATA" ]; then
    echo "ERROR: Bridge Command data directory not found at $BC_DATA"
    exit 1
fi

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial file count in Scenarios folder
ls -1R "$BC_DATA/Scenarios" | wc -l > /tmp/initial_file_count.txt

# Setup window for the agent (Launch Bridge Command)
# We launch it so the agent can test their scenario if they want, 
# or just see the environment.
echo "Starting Bridge Command launcher..."
# Kill any existing instances
pkill -f "bridgecommand" || true
sleep 1

# Launch in background
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_launch.log 2>&1 &"

# Wait for window
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
        echo "Bridge Command window detected."
        break
    fi
    sleep 1
done

# Focus window
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="