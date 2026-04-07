#!/bin/bash
set -e
echo "=== Setting up Progressive Training Suite task ==="

# 1. Define paths
BC_DATA="/opt/bridgecommand"
BC_CONFIG_DIR="/home/ga/.config/Bridge Command"
DOCS_DIR="/home/ga/Documents"

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 3. Clean up previous artifacts (Ensure fresh state)
echo "Cleaning up previous task artifacts..."
rm -rf "$BC_DATA/Scenarios/p) Cadet Module L1 Familiarisation"
rm -rf "$BC_DATA/Scenarios/q) Cadet Module L2 Night Traffic"
rm -rf "$BC_DATA/Scenarios/r) Cadet Module L3 Restricted Vis"
rm -f "$DOCS_DIR/cadet_module_syllabus.txt"

# 4. Reset Configuration (bc5.ini) to defaults
# This ensures we can detect if the agent actually changes the settings
echo "Resetting bc5.ini configuration..."
mkdir -p "$BC_CONFIG_DIR"
cat > "$BC_CONFIG_DIR/bc5.ini" << EOF
[Graphics]
view_angle=90
width=1024
height=768
windowed=1

[Sound]
sound_on=1

[Joystick]
joystick_on=0

[Network]
network_on=0
port=18304

[RADAR]
radar_range_resolution=128
max_radar_range=48
full_radar=0
arpa_on=0
EOF
chown -R ga:ga "$BC_CONFIG_DIR"

# Also copy to program dir as fallback (BC reads both)
cp "$BC_CONFIG_DIR/bc5.ini" "$BC_DATA/bc5.ini" 2>/dev/null || true

# 5. Launch Bridge Command to ensure environment is ready
# We launch it briefly then kill it to ensure assets are loaded/cached if needed
echo "Performing warm-up launch..."
if [ -x "$BC_DATA/bridgecommand" ]; then
    su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /dev/null 2>&1 &"
    sleep 5
    pkill -f "bridgecommand" || true
else
    echo "WARNING: Bridge Command binary not found at $BC_DATA/bridgecommand"
fi

# 6. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="