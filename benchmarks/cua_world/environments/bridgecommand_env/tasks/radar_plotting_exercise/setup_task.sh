#!/bin/bash
echo "=== Setting up Radar Plotting Exercise ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_NAME="o) Solent Radar Plotting Exercise"
SCENARIO_DIR="$BC_DATA/Scenarios/$SCENARIO_NAME"
SOLUTION_FILE="/home/ga/Documents/radar_plotting_solutions.txt"
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous attempts
if [ -d "$SCENARIO_DIR" ]; then
    echo "Removing existing scenario directory..."
    rm -rf "$SCENARIO_DIR"
fi

if [ -f "$SOLUTION_FILE" ]; then
    echo "Removing existing solution file..."
    rm -f "$SOLUTION_FILE"
fi

# 2. Reset bc5.ini to a "clean" state (defaults) so the agent must actively configure it
# We set radar settings to "bad" values to ensure the agent changes them
mkdir -p "$BC_CONFIG_DIR"
cat > "$BC_CONFIG_DIR/bc5.ini" << EOF
[Graphics]
view_angle=90
width=1024
height=768
windowed=1

[RADAR]
arpa_on=0
full_radar=0
radar_range_resolution=64
max_radar_range=24
radar_angular_resolution=360
hide_instruments=0

[Sound]
sound_on=1

[Joystick]
port_throttle_channel=1
stbd_throttle_channel=2
rudder_channel=3
bow_thruster_channel=4
stern_thruster_channel=5
EOF

# Ensure ownership
chown -R ga:ga "$BC_CONFIG_DIR"
chown -R ga:ga /home/ga/Documents

# 3. Launch Bridge Command Launcher (Settings editor is accessed from here)
# We want the agent to see the launcher to access Settings or create scenario
if ! pgrep -f "bridgecommand" > /dev/null; then
    echo "Starting Bridge Command..."
    # Launch in background, cd to data dir required
    su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /dev/null 2>&1 &"
    sleep 5
fi

# 4. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "bridge command"; then
        echo "Bridge Command window detected"
        break
    fi
    sleep 1
done

# Focus the window
DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="