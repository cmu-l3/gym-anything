#!/bin/bash
echo "=== Setting up synchronized_collision_setup task ==="

BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/z) Stress Test"

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Cleanup previous runs
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# 3. Ensure Bridge Command is installed (sanity check)
if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found"
    exit 1
fi

# 4. Kill any running instances
pkill -f "bridgecommand" 2>/dev/null || true

# 5. Capture initial state screenshot
# Just capture the desktop to prove clean state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Task ready: Create scenario at '$SCENARIO_DIR'"