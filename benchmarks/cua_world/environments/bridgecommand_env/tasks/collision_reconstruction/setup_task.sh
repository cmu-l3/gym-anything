#!/bin/bash
echo "=== Setting up collision_reconstruction task ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/n) Solent Collision Reconstruction"
REPORT_FILE="/home/ga/Documents/incident_analysis_report.txt"
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_DATA="$BC_DATA/bc5.ini"

# 1. Clean up previous artifacts to ensure a fresh start
echo "Cleaning up previous task artifacts..."
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$REPORT_FILE" 2>/dev/null || true
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 2. Reset Bridge Command configuration to defaults (disable ARPA/Radar)
# This ensures the agent must explicitly configure them
echo "Resetting bc5.ini configuration..."
mkdir -p "$(dirname "$BC_CONFIG_USER")"

# Create a default config with radar settings turned OFF/Default
cat > /tmp/bc5_default.ini << EOF
[Graphics]
view_angle=90
[RADAR]
arpa_on=0
full_radar=0
max_radar_range=48
radar_range_resolution=128
[Startup]
EOF

cp /tmp/bc5_default.ini "$BC_CONFIG_USER"
cp /tmp/bc5_default.ini "$BC_CONFIG_DATA" 2>/dev/null || true
chown -R ga:ga "/home/ga/.config"

# 3. Timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 4. Launch Bridge Command Launcher
# The agent needs to verify their scenario or use the settings editor
echo "Starting Bridge Command..."
if ! pgrep -f "bridgecommand" > /dev/null; then
    # Must run from data directory
    su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_launch.log 2>&1 &"
    sleep 5
fi

# 5. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
        echo "Bridge Command window detected"
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r "Bridge Command" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true

# 6. Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="