#!/bin/bash
set -euo pipefail

echo "=== Setting up weather_stations_csv_import task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# ================================================================
# PREPARE THE CSV DATA FILE (Real NOAA Weather Station Data)
# ================================================================
DATA_DIR="/home/ga/Documents"
CSV_FILE="$DATA_DIR/noaa_stations.csv"

mkdir -p "$DATA_DIR"

# Create the CSV file with real NOAA GHCN weather station data
# These are actual station IDs, names, and coordinates from NOAA
cat > "$CSV_FILE" << 'CSVEOF'
station_id,station_name,latitude,longitude,elevation_m,state
USW00023174,LOS ANGELES INTL AP,33.9381,-118.3889,32,CA
USW00023234,SAN FRANCISCO INTL AP,37.6197,-122.3647,3,CA
USW00024233,SEATTLE TACOMA INTL AP,47.4444,-122.3138,132,WA
USW00023183,SAN DIEGO LINDBERGH FLD,32.7336,-117.1831,9,CA
USW00024229,PORTLAND INTL JETPORT,45.5958,-122.6093,6,OR
USW00023155,PHOENIX SKY HARBOR INTL AP,33.4278,-111.9556,337,AZ
USW00023062,DENVER INTL AP,39.8561,-104.6737,1650,CO
USW00024127,SALT LAKE CITY INTL AP,40.7781,-111.9694,1287,UT
USW00023050,ALBUQUERQUE INTL AP,35.0417,-106.6156,1619,NM
USW00024131,BOISE AIR TERMINAL,43.5644,-116.2228,874,ID
USW00094846,RENO TAHOE INTL AP,39.4836,-119.7717,1341,NV
USW00023153,TUCSON INTL AP,32.1167,-110.9411,779,AZ
USW00023154,FLAGSTAFF PULLIAM AP,35.1403,-111.6692,2135,AZ
USW00024128,GRAND JUNCTION WALKER FLD,39.1242,-108.5267,1475,CO
USW00024156,BILLINGS LOGAN INTL AP,45.8064,-108.5428,1088,MT
USW00024243,SPOKANE INTL AP,47.6219,-117.5278,721,WA
USW00094224,MEDFORD ROGUE VALLEY INTL,42.3742,-122.8736,405,OR
USW00023066,EL PASO INTL AP,31.8067,-106.3781,1194,TX
USW00093193,LAS VEGAS MCCARRAN INTL AP,36.0719,-115.1633,659,NV
USW00023160,FRESNO YOSEMITE INTL AP,36.7761,-119.7192,101,CA
USW00024121,COLORADO SPRINGS MUNI AP,38.8058,-104.7008,1872,CO
USW00024089,MISSOULA INTL AP,46.9211,-114.0906,972,MT
USW00024023,GREAT FALLS INTL AP,47.4828,-111.3706,1116,MT
USW00024157,HELENA REGIONAL AP,46.6067,-111.9828,1167,MT
USW00093129,SACRAMENTO EXECUTIVE AP,38.5067,-121.4956,5,CA
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
    # Count existing placemarks
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
    sleep 1
done

# Check if window appeared
if ! wmctrl -l | grep -qi "Google Earth"; then
    echo "WARNING: Google Earth window not detected, retrying..."
    pkill -f google-earth-pro 2>/dev/null || true
    sleep 2
    nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup2.log 2>&1 &
    sleep 10
fi

# Maximize and focus the window
sleep 2
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_initial_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_screenshot.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Import Weather Station Data from CSV"
echo "============================================================"
echo ""
echo "CSV file location: $CSV_FILE"
echo "Contains: 25 NOAA weather stations from western United States"
echo ""
echo "Instructions:"
echo "1. Go to File > Import"
echo "2. Select the CSV file at: $CSV_FILE"
echo "3. In the import dialog, map columns:"
echo "   - 'latitude' -> Latitude"
echo "   - 'longitude' -> Longitude"  
echo "   - 'station_name' -> Name"
echo "4. Complete the import"
echo "5. Verify 25 placemarks appear in My Places"
echo "============================================================"