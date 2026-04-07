#!/bin/bash
echo "=== Setting up Convoy Escort Formation Task ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/n) Channel Convoy Escort"
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
DOCS_DIR="/home/ga/Documents"

# 1. Clean up previous runs
echo "Cleaning previous scenario data..."
rm -rf "$SCENARIO_DIR"
rm -f "$DOCS_DIR/convoy_escort_brief.txt"

# 2. Reset Configuration to Defaults (to ensure agent actually configures it)
echo "Resetting Bridge Command configuration..."
mkdir -p "$BC_CONFIG_DIR"
# Create a default config with ARPA off and wrong radar settings
cat > "$BC_CONFIG_DIR/bc5.ini" << EOF
view_angle=90
look_angle=0
max_radar_range=48
radar_range_resolution=128
full_radar=0
arpa_on=0
hide_instruments=0
EOF
chown -R ga:ga "$BC_CONFIG_DIR"

# Also reset the global data config if it exists
if [ -f "$BC_DATA/bc5.ini" ]; then
    cp "$BC_CONFIG_DIR/bc5.ini" "$BC_DATA/bc5.ini"
fi

# 3. Ensure Documents directory exists
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# 4. Record start time for verification
date +%s > /tmp/task_start_time.txt

# 5. Launch Bridge Command (Menu state)
# We launch it so the agent sees the application, but they will likely work in file system
echo "Launching Bridge Command..."
pkill -f "bridgecommand" 2>/dev/null || true
sleep 1

# Launch in background as ga user
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_log.txt 2>&1 &"

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

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="