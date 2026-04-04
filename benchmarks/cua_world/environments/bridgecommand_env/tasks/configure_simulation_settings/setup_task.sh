#!/bin/bash
echo "=== Setting up configure_simulation_settings task ==="

BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"

if [ ! -x "$BC_BIN" ]; then
    echo "ERROR: Bridge Command binary not found at $BC_BIN"
    exit 1
fi

# Ensure view_angle is set to 90 (the starting value the agent needs to change)
# Reset ALL config locations (BC reads from multiple paths)
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
BC_USER_DATA="/home/ga/.Bridge Command/5.10"
mkdir -p "$BC_CONFIG_DIR"
mkdir -p "$BC_USER_DATA"

# Reset config from the template
cp /workspace/config/bc5.ini "$BC_CONFIG_DIR/bc5.ini"
cp /workspace/config/bc5.ini "$BC_DATA/bc5.ini" 2>/dev/null || true

# Ensure view_angle is 90 in all config locations
sed -i 's/^view_angle=.*/view_angle=90/' "$BC_CONFIG_DIR/bc5.ini"
sed -i 's/^view_angle=.*/view_angle=90/' "$BC_DATA/bc5.ini" 2>/dev/null || true

# Also reset the user data config (where the ini editor actually saves)
if [ -f "$BC_USER_DATA/bc5.ini" ]; then
    sed -i 's/view_angle="[^"]*"/view_angle="90"/' "$BC_USER_DATA/bc5.ini"
    echo "Reset view_angle in $BC_USER_DATA/bc5.ini"
fi

chown -R ga:ga "$BC_CONFIG_DIR"
chown -R ga:ga "/home/ga/.Bridge Command" 2>/dev/null || true

# Record baseline state
BASELINE_VIEW_ANGLE=$(grep -oP 'view_angle=\K[0-9]+' "$BC_CONFIG_DIR/bc5.ini" 2>/dev/null || echo "90")

cat > /tmp/initial_state.json << EOF
{
    "task": "configure_simulation_settings",
    "setting": "view_angle",
    "baseline_value": "$BASELINE_VIEW_ANGLE",
    "target_value": "60",
    "config_file": "$BC_CONFIG_DIR/bc5.ini",
    "program_config": "$BC_DATA/bc5.ini",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Baseline view_angle: $BASELINE_VIEW_ANGLE"

# Kill any existing Bridge Command instance
pkill -f "bridgecommand" 2>/dev/null || true
sleep 2

# Launch Bridge Command from its data directory
echo "Starting Bridge Command..."
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_task.log 2>&1 &"
sleep 8

# Check if Bridge Command started
BC_PID=$(pgrep -f "$BC_BIN" 2>/dev/null | head -1)
if [ -n "$BC_PID" ]; then
    echo "Bridge Command is running (PID $BC_PID)"
else
    echo "WARNING: Bridge Command may not have started"
    cat /tmp/bc_task.log 2>/dev/null || true
fi

# Try to focus the Bridge Command window
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true
sleep 1

# Take initial screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_start.png" 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Task: Click 'Settings: Main', change view_angle from 90 to 60, save and exit"
