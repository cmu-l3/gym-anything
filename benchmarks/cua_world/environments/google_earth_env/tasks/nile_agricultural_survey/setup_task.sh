#!/bin/bash
echo "=== Setting up nile_agricultural_survey task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# ================================================================
# CLEAN UP PREVIOUS TASK ARTIFACTS (before recording timestamp)
# ================================================================
rm -f /home/ga/Documents/nile_agricultural_survey.kmz 2>/dev/null || true
rm -f /home/ga/Documents/nile_survey_3d.png 2>/dev/null || true
rm -f /home/ga/Documents/nile_survey_3d.jpg 2>/dev/null || true

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
chmod 755 /home/ga/Documents

# ================================================================
# RECORD TASK START TIME (after cleanup, for anti-gaming)
# ================================================================
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# ================================================================
# PREPARE CSV DATA FILE (Real Nile corridor survey stations)
# ================================================================
CSV_FILE="/home/ga/Documents/nile_survey_points.csv"

cat > "$CSV_FILE" << 'CSVEOF'
name,latitude,longitude,type,description
Aswan High Dam,24.0286,32.8780,infrastructure,Primary water control structure - capacity 132 km3
Old Aswan Dam,24.0847,32.8785,infrastructure,Low dam built 1902 - hydroelectric generation
Kom Ombo Irrigation Intake,24.4520,32.9285,irrigation,East bank canal intake serving 50000 hectares
Kom Ombo Sugar Mill,24.4680,32.9370,industrial,Sugarcane processing - major water consumer
Gebel el-Silsila Gauge,24.6370,32.9310,monitoring,MWRI flow monitoring station - sandstone gorge
Edfu Irrigation Intake,24.9780,32.8730,irrigation,West bank canal intake - barley and wheat zones
Edfu Water Quality Station,24.9810,32.8695,monitoring,Monthly sampling - salinity and nutrient levels
Esna Barrage,25.2930,32.5540,infrastructure,Flow regulation barrage - navigation lock
Esna Pump Station,25.2975,32.5600,irrigation,East bank lift irrigation - 35000 hectares served
El-Tod Gauge Station,25.5840,32.5360,monitoring,Upstream Luxor flow and sediment monitoring
Luxor West Bank Intake,25.6870,32.6310,irrigation,West bank canal system - sugarcane dominant
Karnak Monitoring Station,25.7188,32.6573,monitoring,Final corridor monitoring point - water quality
CSVEOF

chown ga:ga "$CSV_FILE"
chmod 644 "$CSV_FILE"
echo "CSV file created at: $CSV_FILE"
echo "CSV row count: $(wc -l < "$CSV_FILE")"

# Record CSV file timestamp for verification
stat -c %Y "$CSV_FILE" > /tmp/csv_initial_mtime.txt
stat -c %X "$CSV_FILE" > /tmp/csv_initial_atime.txt

# ================================================================
# RECORD INITIAL STATE OF MYPLACES.KML
# ================================================================
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"

if [ -f "$MYPLACES_FILE" ]; then
    INITIAL_PLACEMARK_COUNT=$(grep -c "<Placemark" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    INITIAL_FOLDER_COUNT=$(grep -c "<Folder" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    cp "$MYPLACES_FILE" /tmp/myplaces_initial.kml 2>/dev/null || true
    stat -c %Y "$MYPLACES_FILE" > /tmp/myplaces_initial_mtime.txt
else
    INITIAL_PLACEMARK_COUNT="0"
    INITIAL_FOLDER_COUNT="0"
    echo "0" > /tmp/myplaces_initial_mtime.txt
fi

echo "$INITIAL_PLACEMARK_COUNT" > /tmp/initial_placemark_count.txt
echo "$INITIAL_FOLDER_COUNT" > /tmp/initial_folder_count.txt
echo "Initial placemark count: $INITIAL_PLACEMARK_COUNT"
echo "Initial folder count: $INITIAL_FOLDER_COUNT"

# ================================================================
# KILL AND RESTART GOOGLE EARTH PRO
# ================================================================
echo "Killing any existing Google Earth instances..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
WINDOW_FOUND=false
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 1
done

# Retry if needed
if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected, retrying..."
    pkill -f google-earth-pro 2>/dev/null || true
    sleep 2
    nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup2.log 2>&1 &
    sleep 10
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
            echo "Google Earth window detected on retry after $i seconds"
            WINDOW_FOUND=true
            break
        fi
        sleep 1
    done
fi

# Maximize and focus the window
sleep 2
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Navigate to the Nile corridor area to provide geographic context
echo "Navigating to Nile corridor (Aswan-Luxor region)..."
DISPLAY=:1 xdotool key ctrl+f
sleep 2
DISPLAY=:1 xdotool type "Aswan, Egypt"
sleep 1
DISPLAY=:1 xdotool key Return
sleep 5

# Close search panel
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

# Record Google Earth process info
GE_PID=$(pgrep -f google-earth-pro | head -1)
echo "$GE_PID" > /tmp/google_earth_pid.txt
echo "Google Earth PID: $GE_PID"

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Nile Corridor Agricultural Water Resource Survey"
echo "============================================================"
echo ""
echo "CSV data file: /home/ga/Documents/nile_survey_points.csv"
echo "  Contains: 12 survey stations along the Nile (Aswan to Luxor)"
echo "  Columns: name, latitude, longitude, type, description"
echo ""
echo "Required deliverables:"
echo "  1. Import CSV (File > Import, map columns)"
echo "  2. Folder: 'Nile Corridor Agricultural Survey'"
echo "  3. Path: 'Nile Main Channel' (25+ waypoints, blue, width 3)"
echo "     From Aswan High Dam to Luxor Temple"
echo "  4. Polygon: 'East Bank Agriculture' near Esna (green, 50% transparent)"
echo "  5. Polygon: 'West Bank Agriculture' near Kom Ombo (green, 50% transparent)"
echo "  6. Screenshot: ~/Documents/nile_survey_3d.png (3D tilted view)"
echo "  7. Export: ~/Documents/nile_agricultural_survey.kmz"
echo "============================================================"
