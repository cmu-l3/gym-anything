#!/bin/bash
set -euo pipefail

echo "=== Exporting weather_stations_csv_import task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task start: $TASK_START"
echo "Task end: $TASK_END"
echo "Duration: $((TASK_END - TASK_START)) seconds"

# ================================================================
# CAPTURE FINAL SCREENSHOT
# ================================================================
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

FINAL_SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_screenshot.png ]; then
    FINAL_SCREENSHOT_EXISTS="true"
    SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# ================================================================
# CHECK MYPLACES.KML FOR IMPORTED PLACEMARKS
# ================================================================
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
MYPLACES_EXISTS="false"
CURRENT_PLACEMARK_COUNT="0"
MYPLACES_MODIFIED="false"
MYPLACES_MTIME="0"

if [ -f "$MYPLACES_FILE" ]; then
    MYPLACES_EXISTS="true"
    CURRENT_PLACEMARK_COUNT=$(grep -c "<Placemark" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    
    # Check if modified since task start
    INITIAL_MTIME=$(cat /tmp/myplaces_initial_mtime.txt 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$INITIAL_MTIME" ] && [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_MODIFIED="true"
    fi
    
    # Copy for verification
    cp "$MYPLACES_FILE" /tmp/myplaces_final.kml 2>/dev/null || true
fi

INITIAL_PLACEMARK_COUNT=$(cat /tmp/initial_placemark_count.txt 2>/dev/null || echo "0")
NEW_PLACEMARKS=$((CURRENT_PLACEMARK_COUNT - INITIAL_PLACEMARK_COUNT))

echo "Placemark counts - Initial: $INITIAL_PLACEMARK_COUNT, Current: $CURRENT_PLACEMARK_COUNT, New: $NEW_PLACEMARKS"

# ================================================================
# CHECK CSV FILE ACCESS (Evidence of import attempt)
# ================================================================
CSV_FILE="/home/ga/Documents/noaa_stations.csv"
CSV_ACCESSED="false"

if [ -f "$CSV_FILE" ]; then
    CURRENT_ATIME=$(stat -c %X "$CSV_FILE" 2>/dev/null || echo "0")
    INITIAL_ATIME=$(cat /tmp/csv_initial_atime.txt 2>/dev/null || echo "0")
    
    if [ "$CURRENT_ATIME" -gt "$INITIAL_ATIME" ]; then
        CSV_ACCESSED="true"
    fi
fi

# ================================================================
# SEARCH FOR STATION NAMES IN MYPLACES.KML
# ================================================================
MATCHING_STATIONS="[]"
STATION_COUNT="0"

if [ -f /tmp/myplaces_final.kml ]; then
    # Search for known station names
    FOUND_STATIONS=""
    
    for STATION in "LOS ANGELES INTL AP" "SAN FRANCISCO INTL AP" "SEATTLE TACOMA INTL AP" "DENVER INTL AP" "PHOENIX SKY HARBOR INTL AP" "SAN DIEGO LINDBERGH FLD" "PORTLAND INTL JETPORT" "SALT LAKE CITY INTL AP" "ALBUQUERQUE INTL AP" "BOISE AIR TERMINAL"; do
        if grep -q "$STATION" /tmp/myplaces_final.kml 2>/dev/null; then
            if [ -z "$FOUND_STATIONS" ]; then
                FOUND_STATIONS="\"$STATION\""
            else
                FOUND_STATIONS="$FOUND_STATIONS, \"$STATION\""
            fi
        fi
    done
    
    MATCHING_STATIONS="[$FOUND_STATIONS]"
    STATION_COUNT=$(echo "$MATCHING_STATIONS" | grep -o '"' | wc -l)
    STATION_COUNT=$((STATION_COUNT / 2))
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_PID=""

if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth-pro" | head -1)
fi

# Get window info
GE_WINDOW_TITLE=""
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# ================================================================
# CREATE JSON RESULT
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "duration_seconds": $((TASK_END - TASK_START)),
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_modified": $MYPLACES_MODIFIED,
    "myplaces_mtime": $MYPLACES_MTIME,
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "current_placemark_count": $CURRENT_PLACEMARK_COUNT,
    "new_placemarks_added": $NEW_PLACEMARKS,
    "csv_file_accessed": $CSV_ACCESSED,
    "matching_station_count": $STATION_COUNT,
    "matching_stations": $MATCHING_STATIONS,
    "google_earth_running": $GE_RUNNING,
    "google_earth_pid": "$GE_PID",
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "final_screenshot_exists": $FINAL_SCREENSHOT_EXISTS,
    "final_screenshot_path": "/tmp/task_final_screenshot.png",
    "myplaces_final_path": "/tmp/myplaces_final.kml"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result Summary ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="