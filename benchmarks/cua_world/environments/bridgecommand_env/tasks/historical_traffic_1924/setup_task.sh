#!/bin/bash
echo "=== Setting up Historical Traffic 1924 task ==="

# Bridge Command Paths
BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"
SCENARIO_PATH="$BC_DATA/Scenarios/h) Solent 1924"

# 1. Clean up any previous attempts to ensure fresh start
if [ -d "$SCENARIO_PATH" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_PATH"
fi
rm -f /home/ga/Documents/1924_manifest.txt

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 4. Launch Bridge Command to the start screen
# This allows the agent to visually check models if they want, 
# though file exploration is also valid.
if ! pgrep -f "bridgecommand" > /dev/null; then
    echo "Starting Bridge Command..."
    # Must cd to data dir for BC to work
    su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
            echo "Bridge Command window detected"
            break
        fi
        sleep 1
    done
fi

# 5. Maximize window
DISPLAY=:1 wmctrl -r "Bridge Command" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="