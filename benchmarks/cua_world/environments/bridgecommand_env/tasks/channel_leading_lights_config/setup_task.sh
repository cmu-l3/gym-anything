#!/bin/bash
set -e
echo "=== Setting up channel_leading_lights_config task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/l) Leading Lights Setup"

# Ensure clean state: Remove the target scenario if it exists
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# Ensure Bridge Command directory structure is valid
if [ ! -d "$BC_DATA/Scenarios" ]; then
    echo "ERROR: Scenarios directory missing!"
    exit 1
fi

# Ensure application is available (launcher)
if ! pgrep -f "bridgecommand" > /dev/null; then
    echo "Starting Bridge Command Launcher..."
    # Launch in background so agent can interact with it if they choose
    su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_setup.log 2>&1 &"
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Bridge Command" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Target Directory: $SCENARIO_DIR"