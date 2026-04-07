#!/bin/bash
set -e
echo "=== Setting up Fog Radar Rule 19 Assessment Task ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/r) Solent Fog Radar Assessment"
DOCS_DIR="/home/ga/Documents"
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
BC_USER_DATA="/home/ga/.Bridge Command/5.10"

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Clean previous state
echo "Cleaning up previous task artifacts..."
rm -rf "$SCENARIO_DIR"
rm -f "$DOCS_DIR/fog_assessment_worksheet.txt"
rm -f "$DOCS_DIR/fog_assessment_answers.txt"
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 3. Reset bc5.ini to defaults (to ensure agent actually configures it)
# We set values distinct from the target values
echo "Resetting configuration..."
mkdir -p "$BC_CONFIG_DIR"
mkdir -p "$BC_USER_DATA"

# Create a default config with standard/low settings
cat > /tmp/bc5_default.ini << EOF
[Graphics]
view_angle=90
[RADAR]
arpa_on=0
full_radar=0
radar_range_resolution=128
max_radar_range=24
radar_angular_resolution=360
hide_instruments=0
EOF

cp /tmp/bc5_default.ini "$BC_CONFIG_DIR/bc5.ini"
cp /tmp/bc5_default.ini "$BC_DATA/bc5.ini" 2>/dev/null || true
# Also copy to user data dir where settings editor saves
cp /tmp/bc5_default.ini "$BC_USER_DATA/bc5.ini" 2>/dev/null || true

chown -R ga:ga "$BC_CONFIG_DIR"
chown -R ga:ga "/home/ga/.Bridge Command" 2>/dev/null || true

# 4. Record initial state
echo "0" > /tmp/initial_scenario_exists.txt
if [ -d "$SCENARIO_DIR" ]; then echo "1" > /tmp/initial_scenario_exists.txt; fi

# 5. Ensure Bridge Command is closed initially
pkill -f "bridgecommand" 2>/dev/null || true
sleep 1

# 6. Launch Bridge Command launcher (so agent can use settings editor or select scenario)
echo "Starting Bridge Command Launcher..."
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_launch.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
        echo "Bridge Command window detected"
        break
    fi
    sleep 1
done

# Focus window
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true
sleep 1

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="