#!/bin/bash
echo "=== Exporting nile_agricultural_survey task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task start: $TASK_START"
echo "Task end: $TASK_END"
echo "Duration: $((TASK_END - TASK_START)) seconds"

# ================================================================
# CAPTURE FINAL SCREENSHOT (before any state changes)
# ================================================================
echo "Capturing final state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

FINAL_SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_state.png ]; then
    FINAL_SCREENSHOT_EXISTS="true"
    SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# ================================================================
# CHECK KMZ OUTPUT FILE
# ================================================================
KMZ_PATH="/home/ga/Documents/nile_agricultural_survey.kmz"
KMZ_EXISTS="false"
KMZ_SIZE="0"
KMZ_MTIME="0"
KMZ_CREATED_DURING_TASK="false"

if [ -f "$KMZ_PATH" ]; then
    KMZ_EXISTS="true"
    KMZ_SIZE=$(stat -c %s "$KMZ_PATH" 2>/dev/null || echo "0")
    KMZ_MTIME=$(stat -c %Y "$KMZ_PATH" 2>/dev/null || echo "0")

    if [ "$KMZ_MTIME" -gt "$TASK_START" ]; then
        KMZ_CREATED_DURING_TASK="true"
        echo "KMZ file was created during task execution"
    else
        echo "WARNING: KMZ file exists but was NOT created during task"
    fi

    echo "KMZ file: $KMZ_PATH"
    echo "  Size: $KMZ_SIZE bytes"
    echo "  Modified: $(date -d @$KMZ_MTIME)"

    # Extract KML from KMZ for analysis
    mkdir -p /tmp/kmz_extract
    cd /tmp/kmz_extract && unzip -o "$KMZ_PATH" '*.kml' 2>/dev/null || true
    cd /
    KMZ_KML_FILE=$(find /tmp/kmz_extract -name '*.kml' -type f 2>/dev/null | head -1)
    if [ -n "$KMZ_KML_FILE" ]; then
        cp "$KMZ_KML_FILE" /tmp/task_output.kml 2>/dev/null || true
        echo "Extracted KML from KMZ: $KMZ_KML_FILE"
    fi
else
    echo "KMZ file NOT found: $KMZ_PATH"
fi

# Also check for any KMZ/KML files in Documents
echo ""
echo "--- All KMZ/KML files in Documents ---"
ls -la /home/ga/Documents/*.kmz /home/ga/Documents/*.kml 2>/dev/null || echo "No KMZ/KML files found"

# ================================================================
# CHECK SCREENSHOT OUTPUT FILE
# ================================================================
SCREENSHOT_PATH="/home/ga/Documents/nile_survey_3d.png"
SS_EXISTS="false"
SS_SIZE="0"
SS_MTIME="0"
SS_CREATED_DURING_TASK="false"

# Also check for jpg variant
if [ ! -f "$SCREENSHOT_PATH" ]; then
    for ext in jpg jpeg PNG JPG JPEG; do
        ALT_PATH="/home/ga/Documents/nile_survey_3d.$ext"
        if [ -f "$ALT_PATH" ]; then
            SCREENSHOT_PATH="$ALT_PATH"
            break
        fi
    done
fi

if [ -f "$SCREENSHOT_PATH" ]; then
    SS_EXISTS="true"
    SS_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    SS_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")

    if [ "$SS_MTIME" -gt "$TASK_START" ]; then
        SS_CREATED_DURING_TASK="true"
        echo "Screenshot was created during task execution"
    fi

    echo "Screenshot file: $SCREENSHOT_PATH"
    echo "  Size: $SS_SIZE bytes"

    # Get image dimensions
    SS_DIMENSIONS=$(identify "$SCREENSHOT_PATH" 2>/dev/null | awk '{print $3}' || echo "unknown")
    echo "  Dimensions: $SS_DIMENSIONS"
else
    SS_DIMENSIONS="unknown"
    echo "Screenshot file NOT found at expected path or common variants"
fi

# ================================================================
# ANALYZE KML CONTENT (from KMZ or myplaces)
# ================================================================
KML_HAS_FOLDER="false"
KML_FOLDER_NAME=""
KML_PATH_COUNT="0"
KML_POLYGON_COUNT="0"
KML_HAS_LINESTRING="false"
KML_LINESTRING_COUNT="0"
KML_PATH_NAMES=""
KML_POLYGON_NAMES=""

# Use extracted KML from KMZ if available, otherwise check myplaces
KML_FILE="/tmp/task_output.kml"
if [ ! -f "$KML_FILE" ]; then
    KML_FILE="/home/ga/.googleearth/myplaces.kml"
fi

if [ -f "$KML_FILE" ]; then
    echo ""
    echo "--- Analyzing KML structure ---"

    # Check for Folder element
    if grep -qi "Nile.*Corridor\|Agricultural.*Survey" "$KML_FILE" 2>/dev/null; then
        KML_HAS_FOLDER="true"
        KML_FOLDER_NAME=$(grep -oP '(?<=<name>).*?(?=</name>)' "$KML_FILE" 2>/dev/null | grep -i "Nile\|Agricultural\|Survey" | head -1 || echo "")
        echo "Target folder found: $KML_FOLDER_NAME"
    fi

    # Count LineString elements (paths)
    if grep -qi "<LineString>" "$KML_FILE" 2>/dev/null; then
        KML_HAS_LINESTRING="true"
        KML_LINESTRING_COUNT=$(grep -c "<LineString>" "$KML_FILE" 2>/dev/null || true)
        [ -z "$KML_LINESTRING_COUNT" ] && KML_LINESTRING_COUNT=0
        echo "LineString elements: $KML_LINESTRING_COUNT"
    fi

    # Count Polygon elements
    KML_POLYGON_COUNT=$(grep -c "<Polygon>" "$KML_FILE" 2>/dev/null || true)
    [ -z "$KML_POLYGON_COUNT" ] && KML_POLYGON_COUNT=0
    echo "Polygon elements: $KML_POLYGON_COUNT"

    # Count Placemark elements
    KML_PATH_COUNT=$(grep -c "<Placemark>" "$KML_FILE" 2>/dev/null || true)
    [ -z "$KML_PATH_COUNT" ] && KML_PATH_COUNT=0
    echo "Placemark elements: $KML_PATH_COUNT"

    # Extract path/polygon names
    KML_PATH_NAMES=$(grep -oP '(?<=<name>).*?(?=</name>)' "$KML_FILE" 2>/dev/null | grep -i "Nile\|Channel\|Main" | head -3 || echo "")
    KML_POLYGON_NAMES=$(grep -oP '(?<=<name>).*?(?=</name>)' "$KML_FILE" 2>/dev/null | grep -i "Agriculture\|Bank\|East\|West" | head -3 || echo "")
    echo "Path names found: $KML_PATH_NAMES"
    echo "Polygon names found: $KML_POLYGON_NAMES"

    # Count coordinate points in the main path's LineString
    # Extract all coordinates and count comma-separated triples
    LINESTRING_COORDS=$(sed -n '/<LineString>/,/<\/LineString>/p' "$KML_FILE" 2>/dev/null | \
        sed -n '/<coordinates>/,/<\/coordinates>/p' | head -1)
    if [ -n "$LINESTRING_COORDS" ]; then
        # Each coordinate is lon,lat,alt separated by whitespace
        VERTEX_COUNT=$(echo "$LINESTRING_COORDS" | tr -s ' \n\t' '\n' | grep -c ',' 2>/dev/null || true)
        [ -z "$VERTEX_COUNT" ] && VERTEX_COUNT=0
        echo "Path vertex count (approx): $VERTEX_COUNT"
    else
        VERTEX_COUNT="0"
    fi
fi

# ================================================================
# CHECK MYPLACES.KML FOR IMPORTED CSV DATA
# ================================================================
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
MYPLACES_EXISTS="false"
MYPLACES_MODIFIED="false"
MYPLACES_MTIME="0"
CURRENT_PLACEMARK_COUNT="0"

if [ -f "$MYPLACES_FILE" ]; then
    MYPLACES_EXISTS="true"
    CURRENT_PLACEMARK_COUNT=$(grep -c "<Placemark" "$MYPLACES_FILE" 2>/dev/null || true)
    [ -z "$CURRENT_PLACEMARK_COUNT" ] && CURRENT_PLACEMARK_COUNT=0
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")

    INITIAL_MTIME=$(cat /tmp/myplaces_initial_mtime.txt 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$INITIAL_MTIME" ] && [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_MODIFIED="true"
    fi

    cp "$MYPLACES_FILE" /tmp/myplaces_final.kml 2>/dev/null || true
fi

INITIAL_PLACEMARK_COUNT=$(cat /tmp/initial_placemark_count.txt 2>/dev/null || echo "0")
NEW_PLACEMARKS=$((CURRENT_PLACEMARK_COUNT - INITIAL_PLACEMARK_COUNT))
echo "Placemark counts - Initial: $INITIAL_PLACEMARK_COUNT, Current: $CURRENT_PLACEMARK_COUNT, New: $NEW_PLACEMARKS"

# Check for imported station names
MATCHING_STATIONS="[]"
STATION_COUNT="0"
SEARCH_FILE="/tmp/myplaces_final.kml"
# Also search in temporary places or the KMZ KML
if [ -f /tmp/task_output.kml ]; then
    SEARCH_FILE="/tmp/task_output.kml"
fi

if [ -f "$SEARCH_FILE" ]; then
    FOUND_STATIONS=""
    for STATION in "Aswan High Dam" "Kom Ombo Irrigation" "Esna Barrage" "Edfu Irrigation" "Karnak Monitoring" "Gebel el-Silsila" "Luxor West Bank" "El-Tod Gauge" "Old Aswan Dam" "Kom Ombo Sugar"; do
        if grep -q "$STATION" "$SEARCH_FILE" 2>/dev/null || grep -q "$STATION" /tmp/myplaces_final.kml 2>/dev/null; then
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
echo "Matching imported stations: $STATION_COUNT"

# ================================================================
# CHECK CSV FILE ACCESS
# ================================================================
CSV_FILE="/home/ga/Documents/nile_survey_points.csv"
CSV_ACCESSED="false"

if [ -f "$CSV_FILE" ]; then
    CURRENT_ATIME=$(stat -c %X "$CSV_FILE" 2>/dev/null || echo "0")
    INITIAL_ATIME=$(cat /tmp/csv_initial_atime.txt 2>/dev/null || echo "0")

    if [ "$CURRENT_ATIME" -gt "$INITIAL_ATIME" ]; then
        CSV_ACCESSED="true"
    fi
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

GE_WINDOW_TITLE=""
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi
echo "Google Earth running: $GE_RUNNING (PID: $GE_PID)"

# ================================================================
# CREATE JSON RESULT
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "duration_seconds": $((TASK_END - TASK_START)),
    "kmz_exists": $KMZ_EXISTS,
    "kmz_size_bytes": $KMZ_SIZE,
    "kmz_mtime": $KMZ_MTIME,
    "kmz_created_during_task": $KMZ_CREATED_DURING_TASK,
    "kmz_path": "$KMZ_PATH",
    "screenshot_exists": $SS_EXISTS,
    "screenshot_size_bytes": $SS_SIZE,
    "screenshot_mtime": $SS_MTIME,
    "screenshot_created_during_task": $SS_CREATED_DURING_TASK,
    "screenshot_path": "$SCREENSHOT_PATH",
    "screenshot_dimensions": "$SS_DIMENSIONS",
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_modified": $MYPLACES_MODIFIED,
    "myplaces_mtime": $MYPLACES_MTIME,
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "current_placemark_count": $CURRENT_PLACEMARK_COUNT,
    "new_placemarks_added": $NEW_PLACEMARKS,
    "csv_file_accessed": $CSV_ACCESSED,
    "matching_station_count": $STATION_COUNT,
    "matching_stations": $MATCHING_STATIONS,
    "kml_analysis": {
        "has_folder": $KML_HAS_FOLDER,
        "folder_name": "$KML_FOLDER_NAME",
        "has_linestring": $KML_HAS_LINESTRING,
        "linestring_count": $KML_LINESTRING_COUNT,
        "polygon_count": $KML_POLYGON_COUNT,
        "placemark_count": $KML_PATH_COUNT,
        "path_vertex_count": $VERTEX_COUNT
    },
    "google_earth_running": $GE_RUNNING,
    "google_earth_pid": "$GE_PID",
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "final_screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result Summary ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
