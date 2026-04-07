#!/bin/bash
echo "=== Setting up nav_light_drill_set task ==="

BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"
SCENARIOS_DIR="$BC_DATA/Scenarios"

# 1. Clean up any previous attempts at these specific scenarios
echo "Cleaning previous drill scenarios..."
rm -rf "$SCENARIOS_DIR/p) Light Drill 1 - Power Driven" 2>/dev/null
rm -rf "$SCENARIOS_DIR/q) Light Drill 2 - Sailing Vessel" 2>/dev/null
rm -rf "$SCENARIOS_DIR/r) Light Drill 3 - Vessel Restricted Ability" 2>/dev/null
rm -rf "$SCENARIOS_DIR/s) Light Drill 4 - Fishing Vessel" 2>/dev/null
rm -rf "$SCENARIOS_DIR/t) Light Drill 5 - Vessel Aground" 2>/dev/null

# 2. Clean up documents
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/light_drill_answer_key.txt 2>/dev/null
rm -f /home/ga/Documents/light_drill_student_sheet.txt 2>/dev/null
chown -R ga:ga /home/ga/Documents

# 3. Reset bc5.ini to known defaults
echo "Resetting configuration..."
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
mkdir -p "$BC_CONFIG_DIR"
if [ -f /workspace/config/bc5.ini ]; then
    cp /workspace/config/bc5.ini "$BC_CONFIG_DIR/bc5.ini"
    cp /workspace/config/bc5.ini "$BC_DATA/bc5.ini" 2>/dev/null || true
fi
chown -R ga:ga "$BC_CONFIG_DIR"

# 4. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch Bridge Command so the agent can explore Models/ and test
echo "Launching Bridge Command..."
pkill -f "bridgecommand" 2>/dev/null || true
sleep 2

if [ -x "$BC_BIN" ]; then
    su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_startup.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
            echo "Bridge Command window detected"
            break
        fi
        sleep 1
    done
    
    # Maximize
    DISPLAY=:1 wmctrl -r "Bridge Command" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="