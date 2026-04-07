#!/bin/bash
echo "=== Setting up pilot_boarding_exercise task ==="

BC_BIN="/opt/bridgecommand/bridgecommand"
BC_DATA="/opt/bridgecommand"
BC_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
SCENARIO_DIR="$BC_DATA/Scenarios/p) Solent Pilot Boarding Exercise"
CHECKLIST_FILE="/home/ga/Documents/pilot_boarding_checklist.txt"

# Ensure directories exist
mkdir -p "$BC_DATA/Scenarios"
mkdir -p "/home/ga/Documents"
mkdir -p "$(dirname "$BC_CONFIG")"

# 1. Clean previous run artifacts (Anti-Gaming: ensure fresh start)
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$CHECKLIST_FILE" 2>/dev/null || true

# 2. Reset bc5.ini to defaults (so agent must actively change settings)
# We set values distinct from the target values to ensure we detect changes
# Target: arpa_on=1, full_radar=1, range=72, res=256
# Reset to: arpa_on=0, full_radar=0, range=48, res=128
cat > "$BC_CONFIG" << EOF
[Graphics]
view_angle=60
width=1024
height=768
windowed=1

[Sound]
sound_on=1

[Joystick]
joystick_on=0

[Network]
port=18304
is_server=0
server_ip=127.0.0.1

[RADAR]
radar_range_resolution=128
radar_angular_resolution=360
max_radar_range=48
min_radar_range=0.25
arpa_on=0
full_radar=0
hide_instruments=1
EOF

# Copy config to the data directory as well (BC reads both)
cp "$BC_CONFIG" "$BC_DATA/bc5.ini" 2>/dev/null || true
chown -R ga:ga "/home/ga/.config"
chown ga:ga "$BC_DATA/bc5.ini" 2>/dev/null || true

# 3. Record start time (Anti-Gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Launch Bridge Command for warm-up/initial state
# Kill any existing instances
pkill -f "bridgecommand" 2>/dev/null || true
sleep 1

# Launch
echo "Launching Bridge Command..."
su - ga -c "cd $BC_DATA && DISPLAY=:1 ./bridgecommand > /tmp/bc_startup.log 2>&1 &"
sleep 5

# Check if running
if pgrep -f "$BC_BIN" > /dev/null; then
    echo "Bridge Command running."
    # Focus window
    DISPLAY=:1 wmctrl -a "Bridge Command" 2>/dev/null || true
else
    echo "WARNING: Bridge Command failed to start."
fi

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="