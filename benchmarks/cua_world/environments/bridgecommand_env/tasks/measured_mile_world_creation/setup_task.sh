#!/bin/bash
set -e
echo "=== Setting up Measured Mile World Creation Task ==="

# Define paths
BC_DIR="/opt/bridgecommand"
WORLD_DIR="$BC_DIR/World/MeasuredMile"
SCENARIO_DIR="$BC_DIR/Scenarios/m) Measured Mile Trial"

# 1. Clean previous state (Critical for verification)
if [ -d "$WORLD_DIR" ]; then
    echo "Removing existing World directory..."
    rm -rf "$WORLD_DIR"
fi

if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing Scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure permissions allow agent to write to World and Scenarios
# The installation script should have handled this, but we force it here
chown -R ga:ga "$BC_DIR/World"
chown -R ga:ga "$BC_DIR/Scenarios"
chmod -R 775 "$BC_DIR/World"
chmod -R 775 "$BC_DIR/Scenarios"

# 4. Ensure dependencies are available (Python for image generation)
if ! python3 -c "import sys" 2>/dev/null; then
    echo "Installing python3..."
    apt-get update && apt-get install -y python3
fi

# 5. Launch Bridge Command Launcher (to show agent the app works)
# We don't launch the simulation itself, just the launcher or just leave desktop empty
# Agent needs to create files, not necessarily run the sim immediately, 
# but showing the launcher confirms installation.
if ! pgrep -f "bridgecommand" > /dev/null; then
    echo "Starting Bridge Command Launcher..."
    # We execute in background and don't block
    su - ga -c "cd $BC_DIR && DISPLAY=:1 ./bridgecommand > /tmp/bc_launcher.log 2>&1 &"
    sleep 5
fi

# 6. Maximize window if it appeared
DISPLAY=:1 wmctrl -r "Bridge Command" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="