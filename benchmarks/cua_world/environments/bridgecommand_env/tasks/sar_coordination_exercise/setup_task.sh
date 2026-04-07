#!/bin/bash
echo "=== Setting up SAR Coordination Exercise ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/s) Solent SAR Exercise"
SITREP_FILE="/home/ga/Documents/sar_sitrep.txt"

# 1. Clean up previous artifacts to ensure a fresh start
echo "Cleaning up previous scenario files..."
rm -rf "$SCENARIO_DIR" 2>/dev/null || true
rm -f "$SITREP_FILE" 2>/dev/null || true

# 2. Ensure parent directories exist
mkdir -p "$BC_DATA/Scenarios"
mkdir -p "/home/ga/Documents"
mkdir -p "/home/ga/.config/Bridge Command"
chown -R ga:ga "/home/ga/.config/Bridge Command"
chown ga:ga "/home/ga/Documents"

# 3. Reset bc5.ini to a known default state (non-SAR config)
# This forces the agent to actually make the required edits
echo "Resetting bc5.ini..."
if [ -f "/workspace/config/bc5.ini" ]; then
    cp "/workspace/config/bc5.ini" "/home/ga/.config/Bridge Command/bc5.ini"
    # Ensure default values are NOT what we want the agent to set
    sed -i 's/arpa_on=.*/arpa_on=0/' "/home/ga/.config/Bridge Command/bc5.ini"
    sed -i 's/full_radar=.*/full_radar=0/' "/home/ga/.config/Bridge Command/bc5.ini"
    sed -i 's/radar_range_resolution=.*/radar_range_resolution=64/' "/home/ga/.config/Bridge Command/bc5.ini"
else
    # Fallback creation if template missing
    cat > "/home/ga/.config/Bridge Command/bc5.ini" << EOF
[Graphics]
view_angle=90
[RADAR]
arpa_on=0
full_radar=0
radar_range_resolution=64
max_radar_range=24
EOF
fi
chown ga:ga "/home/ga/.config/Bridge Command/bc5.ini"

# 4. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 5. Take initial screenshot (desktop view, as app is not running yet)
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "State prepared: Scenario directory removed, bc5.ini reset."