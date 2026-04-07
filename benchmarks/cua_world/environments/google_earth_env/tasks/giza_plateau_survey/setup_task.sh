#!/bin/bash
set -euo pipefail

echo "=== Setting up Giza Plateau Archaeological Survey task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# ================================================================
# PREPARE THE CSV DATA FILE (Real Archaeological Reference Data)
# ================================================================
DATA_DIR="/home/ga/Documents"
CSV_FILE="$DATA_DIR/giza_reference_points.csv"

mkdir -p "$DATA_DIR"
chown ga:ga "$DATA_DIR"

# Create CSV file with real Giza Plateau survey reference points
# Coordinates are verified against Google Earth satellite imagery
cat > "$CSV_FILE" << 'CSVEOF'
point_id,name,latitude,longitude,type,notes
GP-001,Khufu Pyramid Center,29.9792,31.1342,pyramid,Great Pyramid of Giza
GP-002,Khafre Pyramid Center,29.9761,31.1308,pyramid,Second Pyramid
GP-003,Menkaure Pyramid Center,29.9725,31.1281,pyramid,Third Pyramid
GP-004,Great Sphinx,29.9753,31.1376,monument,Sphinx body center
GP-005,Valley Temple of Khafre,29.9741,31.1378,temple,Near Sphinx
GP-006,Solar Boat Museum,29.9780,31.1350,museum,South face of Great Pyramid
GP-007,Queens Pyramids,29.9775,31.1365,pyramid,East of Great Pyramid
GP-008,Workers Village,29.9710,31.1310,archaeological,Southern plateau
CSVEOF

chown ga:ga "$CSV_FILE"
chmod 644 "$CSV_FILE"
echo "CSV file created at: $CSV_FILE"
echo "CSV row count: $(wc -l < "$CSV_FILE")"

# Record CSV file timestamps for access verification
stat -c %Y "$CSV_FILE" > /tmp/csv_initial_mtime.txt
stat -c %X "$CSV_FILE" > /tmp/csv_initial_atime.txt

# ================================================================
# REMOVE PREVIOUS OUTPUTS (before recording timestamp)
# ================================================================
rm -f /home/ga/Documents/giza_plateau_survey.kml 2>/dev/null || true
rm -f /home/ga/Documents/giza_plateau_survey.kmz 2>/dev/null || true
rm -f /home/ga/Documents/giza_overview.png 2>/dev/null || true
rm -f /home/ga/Documents/giza_overview.jpg 2>/dev/null || true

# ================================================================
# RECORD TASK START TIME (CRITICAL for anti-gaming)
# Must come AFTER deleting stale outputs
# ================================================================
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "csv_file_created": true,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# ================================================================
# RECORD INITIAL STATE OF MYPLACES.KML
# ================================================================
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"

if [ -f "$MYPLACES_FILE" ]; then
    INITIAL_PLACEMARK_COUNT=$(grep -c "<Placemark" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    cp "$MYPLACES_FILE" /tmp/myplaces_initial.kml 2>/dev/null || true
    stat -c %Y "$MYPLACES_FILE" > /tmp/myplaces_initial_mtime.txt
else
    INITIAL_PLACEMARK_COUNT="0"
    echo "0" > /tmp/myplaces_initial_mtime.txt
fi

echo "$INITIAL_PLACEMARK_COUNT" > /tmp/initial_placemark_count.txt
echo "Initial placemark count: $INITIAL_PLACEMARK_COUNT"

# ================================================================
# RESET TERRAIN EXAGGERATION TO DEFAULT (1.0)
# ================================================================
echo "Resetting terrain exaggeration to default (1.0)..."

CONFIG_DIR="/home/ga/.config/Google"
EARTH_DIR="/home/ga/.googleearth"

mkdir -p "$CONFIG_DIR"
mkdir -p "$EARTH_DIR"

for config_file in "$CONFIG_DIR/GoogleEarthPro.conf" "$EARTH_DIR/GoogleEarthPro.conf" "$EARTH_DIR/myplaces.kml"; do
    if [ -f "$config_file" ]; then
        sed -i 's/elevationExaggeration=[0-9.]*/elevationExaggeration=1.0/g' "$config_file" 2>/dev/null || true
        sed -i 's/terrainExaggeration=[0-9.]*/terrainExaggeration=1.0/g' "$config_file" 2>/dev/null || true
        sed -i 's/<exaggeration>[0-9.]*<\/exaggeration>/<exaggeration>1.0<\/exaggeration>/g' "$config_file" 2>/dev/null || true
        echo "Reset exaggeration in: $config_file"
    fi
done

chown -R ga:ga "$CONFIG_DIR" 2>/dev/null || true
chown -R ga:ga "$EARTH_DIR" 2>/dev/null || true
chown -R ga:ga /home/ga/ 2>/dev/null || true

# ================================================================
# START GOOGLE EARTH PRO
# ================================================================
echo "Killing any existing Google Earth instances..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..45}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 2
done

# Retry if window didn't appear
if ! wmctrl -l | grep -qi "Google Earth"; then
    echo "WARNING: Google Earth window not detected, retrying..."
    pkill -f google-earth-pro 2>/dev/null || true
    sleep 2
    nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup2.log 2>&1 &
    sleep 10
fi

# Additional wait for full initialization
sleep 5

# Dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus the window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Giza Plateau Archaeological Survey and Documentation"
echo "============================================================"
echo ""
echo "You are a GIS analyst creating a digital survey of the Giza"
echo "Plateau for the Egyptian Ministry of Tourism and Antiquities."
echo ""
echo "1. Import reference data:"
echo "   File > Import > $CSV_FILE"
echo "   Map: latitude -> Latitude, longitude -> Longitude, name -> Name"
echo ""
echo "2. Create folder 'Giza Plateau Survey 2025' in My Places"
echo "   Add subfolders: 'Pyramid Complex', 'Supporting Structures'"
echo ""
echo "3. Navigate to Giza Plateau (~29.976N, 31.131E)"
echo ""
echo "4. Create placemarks in 'Pyramid Complex' subfolder:"
echo "   - Great Pyramid of Khufu (29.9792N, 31.1342E)"
echo "   - Pyramid of Khafre (29.9761N, 31.1308E)"
echo "   - Pyramid of Menkaure (29.9725N, 31.1281E)"
echo ""
echo "5. Measure distances between consecutive pyramids (Ruler tool)"
echo ""
echo "6. Create placemarks in 'Supporting Structures':"
echo "   - Great Sphinx (29.9753N, 31.1376E)"
echo "   - Valley Temple of Khafre (29.9741N, 31.1378E)"
echo ""
echo "7. Create path 'Khafre Causeway' (Valley Temple -> Khafre)"
echo "   Follow visible causeway remains, at least 5 waypoints"
echo ""
echo "8. Set terrain exaggeration to 2.0x (Tools > Options > 3D View)"
echo "   Tilt view to 3D perspective from southeast"
echo ""
echo "9. Export folder as KML: /home/ga/Documents/giza_plateau_survey.kml"
echo "   Save screenshot: /home/ga/Documents/giza_overview.png"
echo "============================================================"
