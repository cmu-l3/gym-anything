#!/bin/bash
set -e
echo "=== Setting up create_facility_map task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Generate the Floor Plan Image
echo "Generating floor plan image..."
mkdir -p /home/ga/Documents

# Create a visual floor plan using ImageMagick
# White background, black walls, labeled zones
convert -size 1280x720 xc:white \
    -stroke black -strokewidth 5 -fill none -draw "rectangle 50,50 1230,670" \
    -stroke black -strokewidth 3 -draw "line 50,500 1230,500" \
    -pointsize 40 -fill black -stroke none -gravity south -annotate +0+20 "MAIN ENTRANCE" \
    -fill "#ffcccc" -stroke black -strokewidth 2 -draw "rectangle 900,50 1230,250" \
    -fill red -stroke none -gravity northeast -annotate +50+100 "SERVER\nROOM" \
    -gravity center -fill gray -annotate +0+0 "WAREHOUSE FLOOR" \
    /home/ga/Documents/warehouse_plan.png

chown ga:ga /home/ga/Documents/warehouse_plan.png
chmod 644 /home/ga/Documents/warehouse_plan.png

# 2. Prepare Nx Witness Desktop Client
# (Reusing robust launch logic from environment examples)

# Kill existing instances
pkill -f "applauncher" 2>/dev/null || true
pkill -f "client.*networkoptix" 2>/dev/null || true
pkill -f "nxwitness" 2>/dev/null || true
sleep 2

# Handle keyring to prevent password prompts
mkdir -p /home/ga/.local/share/keyrings 2>/dev/null || true
if [ ! -f /home/ga/.local/share/keyrings/login.keyring ] && [ ! -f /home/ga/.local/share/keyrings/default.keyring ]; then
    # Create dummy keyring file if needed, or rely on system defaults
    true
fi

# Find applauncher
APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)

if [ -n "$APPLAUNCHER" ]; then
    echo "Launching Nx Witness desktop client..."
    # Launch as ga user
    su - ga -c "DISPLAY=:1 $APPLAUNCHER" &
    CLIENT_PID=$!
    
    # Wait for window
    echo "Waiting for client window..."
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Nx Witness"; then
            echo "Client window found"
            break
        fi
        sleep 1
    done
    sleep 5

    # Attempt to dismiss common startup dialogs via coordinate clicks
    # (These coordinates are heuristic based on standard 1920x1080 resolution)
    
    # "Choose password for new keyring" -> Continue
    DISPLAY=:1 xdotool mousemove 1060 678 click 1 2>/dev/null || true
    sleep 1
    
    # "Store passwords unencrypted?" -> Continue
    DISPLAY=:1 xdotool mousemove 1060 628 click 1 2>/dev/null || true
    sleep 1
    
    # EULA -> I Agree
    DISPLAY=:1 xdotool mousemove 1327 783 click 1 2>/dev/null || true
    sleep 3

    # Maximize window
    DISPLAY=:1 wmctrl -r "Nx Witness" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    
else
    echo "WARNING: Nx Witness Desktop Client not found!"
fi

# 3. Authenticate API and Record Initial State
refresh_nx_token > /dev/null 2>&1 || true
INITIAL_LAYOUTS=$(count_layouts 2>/dev/null || echo "0")
echo "$INITIAL_LAYOUTS" > /tmp/initial_layout_count.txt

# 4. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="