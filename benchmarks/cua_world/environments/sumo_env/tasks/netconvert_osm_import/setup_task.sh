#!/bin/bash
echo "=== Setting up netconvert_osm_import task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create working directory
WORK_DIR="/home/ga/SUMO_Scenarios/osm_import"
mkdir -p "$WORK_DIR"

# Download real OSM data for Central Bologna via Overpass API
echo "Downloading OSM extract for central Bologna..."
OSM_FILE="$WORK_DIR/bologna_center.osm"
OVERPASS_QUERY="[out:xml];(way[\"highway\"](44.490,11.335,44.500,11.350);node(w););out body;"

# Try up to 3 times to download the OSM data
for i in {1..3}; do
    curl -s -g "https://overpass-api.de/api/interpreter?data=$OVERPASS_QUERY" -o "$OSM_FILE"
    
    # Check if file is valid XML and contains <osm> tag
    if grep -q "<osm" "$OSM_FILE" 2>/dev/null; then
        echo "OSM data downloaded successfully."
        break
    else
        echo "Download attempt $i failed or returned invalid data. Retrying in 5 seconds..."
        sleep 5
    fi
done

if ! grep -q "<osm" "$OSM_FILE" 2>/dev/null; then
    echo "ERROR: Failed to download real OSM data. Task setup failed."
    exit 1
fi

# Set proper permissions
chown -R ga:ga "$WORK_DIR"

# Make sure no pre-existing output files are present
rm -f "$WORK_DIR/bologna_center.net.xml"

# Launch a terminal for the user in the working directory
echo "Launching terminal..."
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$WORK_DIR &"
    sleep 3
fi

# Maximize the terminal window
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Wait a moment for UI to stabilize
sleep 1

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="