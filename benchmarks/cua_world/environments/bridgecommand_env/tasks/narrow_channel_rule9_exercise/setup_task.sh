#!/bin/bash
set -e
echo "=== Setting up narrow_channel_rule9_exercise task ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/p) Southampton Water Rule 9 Exercise"
BRIEFING_FILE="/home/ga/Documents/rule9_channel_briefing.txt"
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
BC_USER_DATA="/home/ga/.Bridge Command/5.10"

# 1. Clean state: Remove scenario if it exists
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

# 2. Clean state: Remove briefing document
if [ -f "$BRIEFING_FILE" ]; then
    echo "Removing existing briefing document..."
    rm -f "$BRIEFING_FILE"
fi

# 3. Clean state: Reset bc5.ini to defaults (ARPA off, etc.)
echo "Resetting configuration..."
mkdir -p "$BC_CONFIG_DIR"
mkdir -p "$BC_USER_DATA"

# Create a default config with features disabled so agent must enable them
cat > "$BC_CONFIG_DIR/bc5.ini" << EOF
view_angle=90
mouse_sensitivity=1.0
max_radar_range=24
radar_range_resolution=64
full_radar=0
arpa_on=0
hide_instruments=0
radar_angular_resolution=360
EOF

# Copy to other config locations BC might use
cp "$BC_CONFIG_DIR/bc5.ini" "$BC_DATA/bc5.ini" 2>/dev/null || true
cp "$BC_CONFIG_DIR/bc5.ini" "$BC_USER_DATA/bc5.ini" 2>/dev/null || true

# Set permissions
chown -R ga:ga "$BC_CONFIG_DIR"
chown -R ga:ga "/home/ga/.Bridge Command" 2>/dev/null || true
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 4. Anti-gaming: Record start time
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 5. Launch Bridge Command (to show available tools)
echo "Launching Bridge Command..."
pkill -f "bridgecommand" 2>/dev/null || true
sleep 1

# Launch in background
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_launch.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Bridge Command"; then
        echo "Bridge Command window detected."
        break
    fi
    sleep 1
done

# Focus window
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true

# 6. Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="