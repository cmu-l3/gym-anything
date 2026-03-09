#!/bin/bash
set -e
echo "=== Setting up Yellowstone KML Import Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create documents directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Create the KML file with real Yellowstone coordinates
cat > /home/ga/Documents/grand_prismatic_trail.kml << 'KMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Grand Prismatic Trail</name>
    <description>Trail waypoints for Grand Prismatic Spring boardwalk, Yellowstone National Park</description>
    <Style id="trailMarker">
      <IconStyle>
        <scale>1.2</scale>
        <Icon>
          <href>http://maps.google.com/mapfiles/kml/pushpin/ylw-pushpin.png</href>
        </Icon>
      </IconStyle>
      <LabelStyle>
        <scale>0.9</scale>
      </LabelStyle>
    </Style>
    <Folder>
      <name>Grand Prismatic Waypoints</name>
      <open>1</open>
      <Placemark>
        <name>Trailhead Parking</name>
        <description>Fairy Falls trailhead parking area - start of hike to Grand Prismatic overlook</description>
        <styleUrl>#trailMarker</styleUrl>
        <Point>
          <coordinates>-110.8381,44.5252,0</coordinates>
        </Point>
      </Placemark>
      <Placemark>
        <name>Boardwalk Start</name>
        <description>Beginning of Grand Prismatic overlook boardwalk trail</description>
        <styleUrl>#trailMarker</styleUrl>
        <Point>
          <coordinates>-110.8356,44.5256,0</coordinates>
        </Point>
      </Placemark>
      <Placemark>
        <name>Overlook Platform</name>
        <description>Main elevated viewing platform for Grand Prismatic Spring - best photo spot</description>
        <styleUrl>#trailMarker</styleUrl>
        <Point>
          <coordinates>-110.8318,44.5273,0</coordinates>
        </Point>
      </Placemark>
      <Placemark>
        <name>Grand Prismatic Center</name>
        <description>Center of Grand Prismatic Spring - largest hot spring in USA, third largest in world</description>
        <styleUrl>#trailMarker</styleUrl>
        <Point>
          <coordinates>-110.8380,44.5250,0</coordinates>
        </Point>
      </Placemark>
    </Folder>
  </Document>
</kml>
KMLEOF

chown ga:ga /home/ga/Documents/grand_prismatic_trail.kml
chmod 644 /home/ga/Documents/grand_prismatic_trail.kml

# Record KML file initial state
KML_INITIAL_ATIME=$(stat -c %X /home/ga/Documents/grand_prismatic_trail.kml 2>/dev/null || echo "0")
echo "$KML_INITIAL_ATIME" > /tmp/kml_initial_atime.txt

# Remove any existing screenshot to ensure fresh creation
rm -f /home/ga/Documents/grand_prismatic_imported.png 2>/dev/null || true

# Record initial myplaces.kml state if it exists
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
if [ -f "$MYPLACES_PATH" ]; then
    MYPLACES_INITIAL_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    MYPLACES_INITIAL_SIZE=$(stat -c %s "$MYPLACES_PATH" 2>/dev/null || echo "0")
else
    MYPLACES_INITIAL_MTIME="0"
    MYPLACES_INITIAL_SIZE="0"
fi
echo "$MYPLACES_INITIAL_MTIME" > /tmp/myplaces_initial_mtime.txt
echo "$MYPLACES_INITIAL_SIZE" > /tmp/myplaces_initial_size.txt

# Kill any existing Google Earth for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Launch Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_kml.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 2
done

# Maximize and focus Google Earth window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs (Tips, Welcome, etc.)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
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
echo "TASK: Import KML file and navigate to Yellowstone waypoints"
echo "============================================================"
echo ""
echo "KML file location: /home/ga/Documents/grand_prismatic_trail.kml"
echo "Save screenshot to: /home/ga/Documents/grand_prismatic_imported.png"
echo ""
echo "Steps:"
echo "  1. Open File menu and select Open (or press Ctrl+O)"
echo "  2. Navigate to /home/ga/Documents/grand_prismatic_trail.kml"
echo "  3. Import the file"
echo "  4. Find the imported 'Grand Prismatic Trail' in Places panel"
echo "  5. Double-click to fly to the location"
echo "  6. Save screenshot via File > Save > Save Image"
echo "============================================================"