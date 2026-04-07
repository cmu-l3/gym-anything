#!/bin/bash
echo "=== Setting up Emergency Towing Exercise ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/n) Dover Strait ETV Exercise"
DOC_FILE="/home/ga/Documents/emergency_towing_procedure.txt"
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_GLOBAL="$BC_DATA/bc5.ini"

# 1. Clean up previous run artifacts
echo "Cleaning up previous scenario files..."
rm -rf "$SCENARIO_DIR"
rm -f "$DOC_FILE"

# 2. Reset Configuration to defaults (disable ARPA/Radar to force agent to set it)
echo "Resetting Bridge Command configuration..."
# Create user config dir if missing
mkdir -p "$(dirname "$BC_CONFIG_USER")"

# Write a basic default config (ARPA off)
cat > "$BC_CONFIG_USER" << EOF
[Graphics]
view_angle=90
width=1024
height=768
window_mode=0

[RADAR]
arpa_on=0
full_radar=0
max_radar_range=24
radar_range_resolution=64
EOF

# Copy to global location just in case
cp "$BC_CONFIG_USER" "$BC_CONFIG_GLOBAL" 2>/dev/null || true
chown ga:ga "$BC_CONFIG_USER"

# 3. Open File Manager to help agent start
echo "Opening file manager..."
su - ga -c "DISPLAY=:1 nautilus /opt/bridgecommand/Scenarios &"
sleep 2

# 4. Open Text Editor for the document
echo "Opening text editor..."
su - ga -c "DISPLAY=:1 gedit &"
sleep 2

# 5. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 6. Take initial screenshot
DISPLAY=:1 wmctrl -r "Scenarios" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="