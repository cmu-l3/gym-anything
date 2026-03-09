#!/bin/bash
set -euo pipefail

echo "=== Setting up animated_architecture_tour task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure X server access
xhost +local: 2>/dev/null || true

# Create output directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any existing output files (clean state)
rm -f /home/ga/Documents/architecture_tour.kmz 2>/dev/null || true
rm -f /home/ga/Documents/architecture_tour.kml 2>/dev/null || true

# Record initial state - check for any existing KMZ/KML files
INITIAL_KMZ_COUNT=$(find /home/ga/Documents -name "*.kmz" -o -name "*.kml" 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_KMZ_COUNT" > /tmp/initial_kmz_count.txt
echo "Initial KMZ/KML file count: $INITIAL_KMZ_COUNT"

# Clear Google Earth's My Places to start fresh (backup first)
GE_DIR="/home/ga/.googleearth"
mkdir -p "$GE_DIR"
chown ga:ga "$GE_DIR"

if [ -f "$GE_DIR/myplaces.kml" ]; then
    cp "$GE_DIR/myplaces.kml" "$GE_DIR/myplaces.kml.backup.$(date +%s)" 2>/dev/null || true
fi

# Create clean myplaces.kml
cat > "$GE_DIR/myplaces.kml" << 'MYPLACES_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
    <name>My Places</name>
    <open>1</open>
</Document>
</kml>
MYPLACES_EOF
chown ga:ga "$GE_DIR/myplaces.kml"

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_tour.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Save initial state summary
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "initial_kmz_count": $INITIAL_KMZ_COUNT,
    "output_kmz_exists": false,
    "output_kml_exists": false,
    "google_earth_running": true,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Create an animated fly-through tour"
echo "============================================================"
echo ""
echo "Create placemarks at these three locations:"
echo "  1. Sydney Opera House, Sydney, Australia"
echo "  2. Burj Khalifa, Dubai, UAE"
echo "  3. Guggenheim Museum Bilbao, Spain"
echo ""
echo "Then:"
echo "  - Create a folder named 'Modern Architecture Tour'"
echo "  - Move all placemarks into the folder"
echo "  - Record a tour of the locations"
echo "  - Save as: ~/Documents/architecture_tour.kmz"
echo ""
echo "============================================================"