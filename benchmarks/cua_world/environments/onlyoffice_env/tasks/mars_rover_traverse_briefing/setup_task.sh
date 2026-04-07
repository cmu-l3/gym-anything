#!/bin/bash
set -euo pipefail

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

echo "=== Setting up Mars Rover Traverse Briefing Task ==="

# Record task start timestamp (subtract 5 seconds for safety margin on file checks)
echo $(( $(date +%s) - 5 )) > /tmp/mars_task_start_ts

# Cleanup from previous runs
rm -f /tmp/mars_task_result.json 2>/dev/null || true
pkill -f "onlyoffice-desktopeditors|DesktopEditors" 2>/dev/null || true
sleep 1

# Setup Directories
WORKSPACE_DIR="/home/ga/Documents/Mars_Briefing"
PRESENTATIONS_DIR="/home/ga/Documents/Presentations"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$PRESENTATIONS_DIR"

# 1. Create Briefing Notes
cat > "$WORKSPACE_DIR/briefing_notes.txt" << 'EOF'
Title: Jezero Delta Front Traverse
Subtitle: Science Team Briefing

Science Objectives:
- Characterize the stratigraphy of the delta front
- Identify and sample fine-grained phyllosilicates
- Assess the habitability of the ancient lake environment
- Collect paired samples for Mars Sample Return (MSR)
EOF

# 2. Create Waypoints CSV (Real names/locations from Perseverance Mars 2020 Mission)
cat > "$WORKSPACE_DIR/waypoints_sol_300_320.csv" << 'EOF'
Sol,Site_Name,Easting,Northing,Elevation,Science_Priority
300,Nav_Point_A,772341,2093845,-2541,Low
302,Rochette,772350,2093860,-2538,High
304,Drive_Stop_45,772365,2093890,-2535,Medium
306,Brac,772380,2093915,-2530,High
308,Hazcam_Check,772400,2093940,-2528,Low
311,Quartier,772425,2093970,-2525,High
313,UHF_Pass_Loc,772450,2094000,-2522,Medium
316,Artuby,772480,2094040,-2518,High
318,Nav_Point_B,772500,2094080,-2515,Low
320,Citadelle_Approach,772530,2094120,-2512,Medium
EOF

# 3. Download or create map image
# Try downloading a real NASA HiRISE image of Jezero Crater
if ! wget -q -O "$WORKSPACE_DIR/jezero_map.jpg" "https://mars.nasa.gov/system/resources/detail_files/25088_PIA23999-web.jpg"; then
    echo "Warning: Download failed, generating synthetic placeholder image..."
    if command -v convert &> /dev/null; then
        convert -size 800x600 xc:chocolate -gravity center -pointsize 40 -fill white -draw "text 0,0 'Jezero Crater Map'" "$WORKSPACE_DIR/jezero_map.jpg"
    else
        # Last resort fallback if imagemagick isn't present
        cp /usr/share/backgrounds/gnome/adwaita-day.jpg "$WORKSPACE_DIR/jezero_map.jpg" 2>/dev/null || true
    fi
fi

# Set proper permissions
chown -R ga:ga "$WORKSPACE_DIR"
chown -R ga:ga "$PRESENTATIONS_DIR"

# Start ONLYOFFICE Presentation Editor
echo "Starting ONLYOFFICE Presentation Editor..."
sudo -u ga DISPLAY=:1 /usr/bin/onlyoffice-desktopeditors --new:slide > /tmp/onlyoffice_launch.log 2>&1 &

# Wait for window to appear and maximize it
echo "Waiting for ONLYOFFICE window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE\|Desktop Editors"; then
        WID=$(DISPLAY=:1 wmctrl -l | grep -i 'ONLYOFFICE\|Desktop Editors' | awk '{print $1}' | head -1)
        if [ -n "$WID" ]; then
            DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
            sleep 0.5
            DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
            break
        fi
    fi
    sleep 1
done

# Take Initial Screenshot
echo "Taking initial screenshot..."
sleep 2
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup Complete ==="