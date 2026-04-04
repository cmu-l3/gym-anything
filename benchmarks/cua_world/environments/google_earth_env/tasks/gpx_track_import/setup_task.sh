#!/bin/bash
set -e
echo "=== Setting up GPX Track Import task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming timestamp verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create task directory
TASK_DIR="/home/ga/Documents"
mkdir -p "$TASK_DIR"

# Create the GPX file with real Angel's Landing trail coordinates
GPX_FILE="$TASK_DIR/angels_landing_trail.gpx"

echo "Creating Angel's Landing GPX track file..."
cat > "$GPX_FILE" << 'GPXEOF'
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="ZionTrailData"
     xmlns="http://www.topografix.com/GPX/1/1"
     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
     xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
  <metadata>
    <name>Angel's Landing Trail - Zion National Park</name>
    <desc>Famous hiking trail to Angel's Landing summit in Zion Canyon, Utah. Coordinates from USGS topographic data.</desc>
    <author><name>Zion Trail Documentation</name></author>
  </metadata>
  <trk>
    <name>Angels Landing Trail</name>
    <desc>West Rim Trailhead to Angel's Landing Summit - 4.4 miles round trip, 1488 ft elevation gain</desc>
    <type>Hiking</type>
    <trkseg>
      <!-- Grotto Trailhead -->
      <trkpt lat="37.25941" lon="-112.95082"><ele>1298</ele><name>Grotto Trailhead</name></trkpt>
      <trkpt lat="37.25912" lon="-112.95056"><ele>1302</ele></trkpt>
      <trkpt lat="37.25889" lon="-112.95043"><ele>1305</ele></trkpt>
      <trkpt lat="37.25867" lon="-112.95018"><ele>1311</ele></trkpt>
      <trkpt lat="37.25845" lon="-112.94991"><ele>1318</ele></trkpt>
      <!-- Bridge crossing Virgin River -->
      <trkpt lat="37.25821" lon="-112.94958"><ele>1321</ele></trkpt>
      <trkpt lat="37.25798" lon="-112.94923"><ele>1325</ele></trkpt>
      <trkpt lat="37.25778" lon="-112.94896"><ele>1332</ele></trkpt>
      <trkpt lat="37.25756" lon="-112.94867"><ele>1341</ele></trkpt>
      <!-- Start of West Rim Trail ascent -->
      <trkpt lat="37.25729" lon="-112.94841"><ele>1352</ele></trkpt>
      <trkpt lat="37.25701" lon="-112.94812"><ele>1362</ele></trkpt>
      <trkpt lat="37.25672" lon="-112.94789"><ele>1378</ele></trkpt>
      <trkpt lat="37.25643" lon="-112.94768"><ele>1389</ele></trkpt>
      <trkpt lat="37.25618" lon="-112.94745"><ele>1405</ele></trkpt>
      <trkpt lat="37.25589" lon="-112.94721"><ele>1421</ele></trkpt>
      <trkpt lat="37.25562" lon="-112.94702"><ele>1438</ele></trkpt>
      <trkpt lat="37.25534" lon="-112.94689"><ele>1458</ele></trkpt>
      <!-- Approaching Refrigerator Canyon -->
      <trkpt lat="37.25505" lon="-112.94671"><ele>1475</ele></trkpt>
      <trkpt lat="37.25478" lon="-112.94652"><ele>1492</ele></trkpt>
      <trkpt lat="37.25449" lon="-112.94638"><ele>1512</ele></trkpt>
      <trkpt lat="37.25421" lon="-112.94623"><ele>1531</ele></trkpt>
      <trkpt lat="37.25392" lon="-112.94609"><ele>1548</ele></trkpt>
      <trkpt lat="37.25367" lon="-112.94598"><ele>1567</ele></trkpt>
      <trkpt lat="37.25341" lon="-112.94582"><ele>1582</ele></trkpt>
      <trkpt lat="37.25312" lon="-112.94567"><ele>1598</ele></trkpt>
      <!-- Refrigerator Canyon - narrow slot -->
      <trkpt lat="37.25285" lon="-112.94551"><ele>1612</ele></trkpt>
      <trkpt lat="37.25256" lon="-112.94534"><ele>1625</ele></trkpt>
      <trkpt lat="37.25228" lon="-112.94521"><ele>1638</ele></trkpt>
      <trkpt lat="37.25198" lon="-112.94512"><ele>1651</ele></trkpt>
      <trkpt lat="37.25172" lon="-112.94498"><ele>1662</ele></trkpt>
      <trkpt lat="37.25145" lon="-112.94487"><ele>1672</ele></trkpt>
      <trkpt lat="37.25121" lon="-112.94472"><ele>1681</ele></trkpt>
      <trkpt lat="37.25098" lon="-112.94456"><ele>1689</ele></trkpt>
      <!-- Walter's Wiggles - 21 tight switchbacks -->
      <trkpt lat="37.25075" lon="-112.94438"><ele>1701</ele></trkpt>
      <trkpt lat="37.25052" lon="-112.94423"><ele>1712</ele></trkpt>
      <trkpt lat="37.25043" lon="-112.94408"><ele>1721</ele></trkpt>
      <trkpt lat="37.25034" lon="-112.94398"><ele>1728</ele></trkpt>
      <trkpt lat="37.25026" lon="-112.94412"><ele>1738</ele></trkpt>
      <trkpt lat="37.25018" lon="-112.94398"><ele>1745</ele></trkpt>
      <trkpt lat="37.25009" lon="-112.94412"><ele>1755</ele></trkpt>
      <trkpt lat="37.25001" lon="-112.94389"><ele>1762</ele></trkpt>
      <trkpt lat="37.24994" lon="-112.94405"><ele>1771</ele></trkpt>
      <trkpt lat="37.24987" lon="-112.94389"><ele>1778</ele></trkpt>
      <trkpt lat="37.24979" lon="-112.94398"><ele>1786</ele></trkpt>
      <trkpt lat="37.24971" lon="-112.94382"><ele>1795</ele></trkpt>
      <trkpt lat="37.24964" lon="-112.94398"><ele>1803</ele></trkpt>
      <trkpt lat="37.24958" lon="-112.94382"><ele>1812</ele></trkpt>
      <trkpt lat="37.24951" lon="-112.94391"><ele>1821</ele></trkpt>
      <trkpt lat="37.24942" lon="-112.94375"><ele>1829</ele></trkpt>
      <trkpt lat="37.24935" lon="-112.94389"><ele>1838</ele></trkpt>
      <trkpt lat="37.24928" lon="-112.94375"><ele>1845</ele></trkpt>
      <trkpt lat="37.24921" lon="-112.94382"><ele>1854</ele></trkpt>
      <!-- Scout Lookout -->
      <trkpt lat="37.24912" lon="-112.94367"><ele>1862</ele><name>Scout Lookout</name></trkpt>
      <trkpt lat="37.24895" lon="-112.94356"><ele>1868</ele></trkpt>
      <trkpt lat="37.24878" lon="-112.94345"><ele>1871</ele></trkpt>
      <trkpt lat="37.24862" lon="-112.94328"><ele>1874</ele></trkpt>
      <trkpt lat="37.24845" lon="-112.94312"><ele>1876</ele></trkpt>
      <!-- Angel's Landing spine - chains section -->
      <trkpt lat="37.24828" lon="-112.94295"><ele>1879</ele></trkpt>
      <trkpt lat="37.24812" lon="-112.94278"><ele>1882</ele></trkpt>
      <trkpt lat="37.24795" lon="-112.94261"><ele>1886</ele></trkpt>
      <trkpt lat="37.24778" lon="-112.94245"><ele>1891</ele></trkpt>
      <trkpt lat="37.24762" lon="-112.94228"><ele>1895</ele></trkpt>
      <trkpt lat="37.24745" lon="-112.94212"><ele>1898</ele></trkpt>
      <trkpt lat="37.24728" lon="-112.94195"><ele>1905</ele></trkpt>
      <trkpt lat="37.24712" lon="-112.94178"><ele>1912</ele></trkpt>
      <trkpt lat="37.24695" lon="-112.94161"><ele>1918</ele></trkpt>
      <trkpt lat="37.24679" lon="-112.94145"><ele>1923</ele></trkpt>
      <trkpt lat="37.24662" lon="-112.94128"><ele>1929</ele></trkpt>
      <trkpt lat="37.24645" lon="-112.94112"><ele>1935</ele></trkpt>
      <trkpt lat="37.24628" lon="-112.94095"><ele>1940</ele></trkpt>
      <!-- Angel's Landing Summit -->
      <trkpt lat="37.24612" lon="-112.94078"><ele>1763</ele><name>Angels Landing Summit</name></trkpt>
    </trkseg>
  </trk>
</gpx>
GPXEOF

echo "GPX file created at $GPX_FILE"

# Set proper permissions
chown -R ga:ga "$TASK_DIR"
chmod 644 "$GPX_FILE"

# Record initial state - check if output file already exists (for anti-gaming)
OUTPUT_FILE="$TASK_DIR/angels_landing_visualization.jpg"
if [ -f "$OUTPUT_FILE" ]; then
    INITIAL_OUTPUT_EXISTS="true"
    INITIAL_OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    INITIAL_OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    # Remove pre-existing output to ensure clean state
    rm -f "$OUTPUT_FILE"
    echo "Removed pre-existing output file"
else
    INITIAL_OUTPUT_EXISTS="false"
    INITIAL_OUTPUT_SIZE="0"
    INITIAL_OUTPUT_MTIME="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "gpx_file_exists": true,
    "gpx_file_path": "$GPX_FILE",
    "output_file_existed_before": $INITIAL_OUTPUT_EXISTS,
    "initial_output_size": $INITIAL_OUTPUT_SIZE,
    "initial_output_mtime": $INITIAL_OUTPUT_MTIME,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_gpx.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth Pro window detected"
        break
    fi
    sleep 1
done

# Additional wait for full initialization
sleep 5

# Maximize Google Earth window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus Google Earth window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for evidence
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
echo "TASK: Import GPX track and create terrain visualization"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Import the GPX file: $GPX_FILE"
echo "   (File > Import, then select the .gpx file)"
echo ""
echo "2. Adjust the view to show the complete trail on 3D terrain"
echo "   - The trail is in Zion National Park, Utah"
echo "   - Tilt the view to show elevation changes"
echo ""
echo "3. Export the visualization as an image:"
echo "   (File > Save > Save Image)"
echo "   Save to: $OUTPUT_FILE"
echo "   Resolution: At least 1920x1080"
echo ""
echo "============================================================"