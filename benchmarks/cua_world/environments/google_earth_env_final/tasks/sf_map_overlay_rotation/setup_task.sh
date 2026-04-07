#!/bin/bash
echo "=== Setting up SF Map Overlay Rotation task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure X server access
xhost +local: 2>/dev/null || true

# =============================================================
# PREPARE THE HISTORICAL MAP DATA
# =============================================================
DATA_DIR="/home/ga/Documents"
mkdir -p "$DATA_DIR"

MAP_FILE="$DATA_DIR/sf_1906_map.png"

# Check if map already exists
if [ ! -f "$MAP_FILE" ]; then
    echo "Downloading historical San Francisco map..."
    
    # Try to download from Library of Congress Sanborn Maps collection
    # This is a section of San Francisco from the 1905-1915 era
    # Using the LOC IIIF API for public domain maps
    LOC_URL="https://tile.loc.gov/image-services/iiif/service:gmd:gmd387:g3804:g3804s:pm007860/0,0,2048,2048/1024,/0/default.jpg"
    
    curl -L -o "$MAP_FILE" "$LOC_URL" --connect-timeout 30 --max-time 60 2>/dev/null
    
    if [ ! -f "$MAP_FILE" ] || [ ! -s "$MAP_FILE" ]; then
        echo "Primary download failed, trying alternate source..."
        
        # Alternate: Use a public domain historical map section
        ALT_URL="https://upload.wikimedia.org/wikipedia/commons/thumb/8/85/1853_U.S.C.S._Map_of_San_Francisco%2C_California_-_Geographicus_-_SanFrancisco-uscs-1853.jpg/1024px-1853_U.S.C.S._Map_of_San_Francisco%2C_California_-_Geographicus_-_SanFrancisco-uscs-1853.jpg"
        
        curl -L -o "$MAP_FILE" "$ALT_URL" --connect-timeout 30 --max-time 60 2>/dev/null
    fi
    
    if [ ! -f "$MAP_FILE" ] || [ ! -s "$MAP_FILE" ]; then
        echo "Creating fallback historical-style map..."
        # Create a simple placeholder with street labels that needs rotation
        # This ensures the task can still be completed even if downloads fail
        convert -size 1024x1024 xc:'#f5e6c8' \
            -fill '#8b7355' -stroke '#5c4a32' -strokewidth 2 \
            -draw "line 100,900 900,100" \
            -draw "line 50,700 950,600" \
            -draw "line 200,50 300,950" \
            -font Courier-Bold -pointsize 24 -fill '#3d2914' \
            -draw "rotate -42 text 400,500 'MARKET STREET'" \
            -draw "rotate 0 text 100,650 'MISSION ST'" \
            -draw "text 50,50 'SAN FRANCISCO 1906'" \
            -draw "rectangle 800,800 950,950" \
            -draw "text 810,870 'SCALE'" \
            "$MAP_FILE" 2>/dev/null || {
                # Absolute fallback - create minimal image
                echo "P6 256 256 255" > /tmp/temp.ppm
                head -c $((256*256*3)) /dev/zero | tr '\0' '\377' >> /tmp/temp.ppm
                convert /tmp/temp.ppm -fill '#f5e6c8' -draw "color 0,0 reset" \
                    -fill '#5c4a32' -draw "line 20,230 230,20" \
                    -pointsize 12 -draw "text 60,130 'SF 1906'" \
                    "$MAP_FILE" 2>/dev/null || touch "$MAP_FILE"
            }
    fi
fi

# Verify map file exists
if [ -f "$MAP_FILE" ]; then
    MAP_SIZE=$(stat -c %s "$MAP_FILE" 2>/dev/null || echo "0")
    echo "Map file ready: $MAP_FILE ($MAP_SIZE bytes)"
else
    echo "WARNING: Map file could not be created!"
fi

# Set ownership
chown -R ga:ga "$DATA_DIR" 2>/dev/null || true

# =============================================================
# RECORD INITIAL STATE
# =============================================================
KMZ_OUTPUT="/home/ga/Documents/sf_overlay.kmz"

# Remove any existing output file to ensure clean state
rm -f "$KMZ_OUTPUT" 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "map_file_exists": $([ -f "$MAP_FILE" ] && echo "true" || echo "false"),
    "map_file_size": $(stat -c %s "$MAP_FILE" 2>/dev/null || echo "0"),
    "kmz_exists_before": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# =============================================================
# LAUNCH GOOGLE EARTH PRO
# =============================================================

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth.log 2>&1 &

# Wait for Google Earth window to appear
echo "Waiting for Google Earth to start..."
for i in {1..60}; do
    if wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        break
    fi
    sleep 1
done

sleep 3

# Maximize and focus the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 2

# =============================================================
# NAVIGATE TO SAN FRANCISCO
# =============================================================
echo "Navigating to San Francisco..."

# Use Ctrl+F to open search, then search for San Francisco
DISPLAY=:1 xdotool key ctrl+f
sleep 2

# Type search query
DISPLAY=:1 xdotool type "San Francisco, Market Street and Mission Street, CA"
sleep 1

# Press Enter to search
DISPLAY=:1 xdotool key Return
sleep 5

# Dismiss any search results popup by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus Google Earth window again
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# =============================================================
# TAKE INITIAL SCREENSHOT
# =============================================================
echo "Capturing initial state screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: $SCREENSHOT_SIZE bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "============================================================"
echo "TASK: Create a Historical Map Overlay with Rotation"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Create an Image Overlay: Add > Image Overlay"
echo "2. Browse to: /home/ga/Documents/sf_1906_map.png"
echo "3. Position the overlay over downtown San Francisco"
echo "4. Rotate approximately 9-11 degrees to align Market Street"
echo "5. Set transparency to approximately 50%"
echo "6. Name it: 'SF 1906 Historical Map'"
echo "7. Save to My Places, then export as KMZ to:"
echo "   /home/ga/Documents/sf_overlay.kmz"
echo ""
echo "Map file location: $MAP_FILE"
echo "============================================================"
echo ""
echo "=== Task setup complete ==="