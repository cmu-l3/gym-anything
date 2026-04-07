#!/bin/bash
set -euo pipefail

echo "=== Exporting Thames River Path task result ==="

export DISPLAY=${DISPLAY:-:1}

# Take final screenshot BEFORE any other operations
echo "Capturing final screenshot..."
scrot /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# ================================================================
# GET TIMESTAMPS
# ================================================================
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ================================================================
# CHECK KML FILE
# ================================================================
KML_PATH="/home/ga/Documents/thames_path.kml"
KMZ_PATH="/home/ga/Documents/thames_path.kmz"

KML_EXISTS="false"
KML_SIZE="0"
KML_MTIME="0"
KML_CREATED_DURING_TASK="false"
KML_MODIFIED_DURING_TASK="false"
ACTUAL_PATH=""

# Check for KML first, then KMZ
if [ -f "$KML_PATH" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c%s "$KML_PATH" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c%Y "$KML_PATH" 2>/dev/null || echo "0")
    ACTUAL_PATH="$KML_PATH"
    echo "Found KML file: $KML_PATH (${KML_SIZE} bytes)"
elif [ -f "$KMZ_PATH" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c%s "$KMZ_PATH" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c%Y "$KMZ_PATH" 2>/dev/null || echo "0")
    ACTUAL_PATH="$KMZ_PATH"
    echo "Found KMZ file: $KMZ_PATH (${KML_SIZE} bytes)"
else
    echo "No KML/KMZ file found at expected location"
    # Check if file exists elsewhere in Documents
    FOUND_KML=$(find /home/ga/Documents -name "*.kml" -o -name "*.kmz" 2>/dev/null | head -1)
    if [ -n "$FOUND_KML" ]; then
        KML_EXISTS="true"
        KML_SIZE=$(stat -c%s "$FOUND_KML" 2>/dev/null || echo "0")
        KML_MTIME=$(stat -c%Y "$FOUND_KML" 2>/dev/null || echo "0")
        ACTUAL_PATH="$FOUND_KML"
        echo "Found alternate KML file: $FOUND_KML"
    fi
fi

# Check if file was created/modified during task
if [ "$KML_EXISTS" = "true" ] && [ "$KML_MTIME" != "0" ] && [ "$TASK_START" != "0" ]; then
    # Get initial state
    INITIAL_EXISTS=$(python3 -c "import json; print(str(json.load(open('/tmp/initial_state.json')).get('kml_exists', False)).lower())" 2>/dev/null || echo "false")
    INITIAL_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('kml_mtime', 0))" 2>/dev/null || echo "0")
    
    if [ "$INITIAL_EXISTS" = "false" ] && [ "$KML_MTIME" -gt "$TASK_START" ]; then
        KML_CREATED_DURING_TASK="true"
        echo "File was created during task"
    elif [ "$KML_MTIME" -gt "$INITIAL_MTIME" ] && [ "$KML_MTIME" -gt "$TASK_START" ]; then
        KML_MODIFIED_DURING_TASK="true"
        echo "File was modified during task"
    fi
fi

# ================================================================
# PARSE KML CONTENT (if exists)
# ================================================================
COORDINATE_COUNT="0"
FIRST_COORD_LAT="0"
FIRST_COORD_LON="0"
LAST_COORD_LAT="0"
LAST_COORD_LON="0"
PATH_NAME=""
ALL_COORDINATES=""

if [ "$KML_EXISTS" = "true" ] && [ -n "$ACTUAL_PATH" ]; then
    # If KMZ, extract KML first
    PARSE_PATH="$ACTUAL_PATH"
    if [[ "$ACTUAL_PATH" == *.kmz ]]; then
        echo "Extracting KML from KMZ..."
        mkdir -p /tmp/kmz_extract
        unzip -o "$ACTUAL_PATH" -d /tmp/kmz_extract 2>/dev/null || true
        EXTRACTED_KML=$(find /tmp/kmz_extract -name "*.kml" | head -1)
        if [ -n "$EXTRACTED_KML" ]; then
            PARSE_PATH="$EXTRACTED_KML"
        fi
    fi
    
    # Parse KML using Python
    echo "Parsing KML content..."
    python3 << PYEOF > /tmp/kml_parsed.json 2>/dev/null || echo '{"error": "parse_failed"}' > /tmp/kml_parsed.json
import json
import xml.etree.ElementTree as ET
import re

result = {
    "coordinate_count": 0,
    "first_coord": {"lat": 0, "lon": 0},
    "last_coord": {"lat": 0, "lon": 0},
    "all_coordinates": [],
    "path_name": "",
    "parse_success": False
}

try:
    tree = ET.parse("$PARSE_PATH")
    root = tree.getroot()
    
    # Handle KML namespace
    ns_match = re.match(r'\{.*\}', root.tag)
    ns = ns_match.group(0) if ns_match else ''
    
    # Find path name
    for name_elem in root.iter():
        if name_elem.tag.endswith('name') and name_elem.text:
            result["path_name"] = name_elem.text
            break
    
    # Find coordinates
    for elem in root.iter():
        if elem.tag.endswith('coordinates') and elem.text:
            coord_text = elem.text.strip()
            coords = []
            for coord in coord_text.split():
                parts = coord.strip().split(',')
                if len(parts) >= 2:
                    try:
                        lon = float(parts[0])
                        lat = float(parts[1])
                        coords.append({"lat": lat, "lon": lon})
                    except:
                        pass
            
            if coords:
                result["all_coordinates"] = coords
                result["coordinate_count"] = len(coords)
                result["first_coord"] = coords[0]
                result["last_coord"] = coords[-1]
                result["parse_success"] = True
                break

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    # Extract values from parsed JSON
    if [ -f /tmp/kml_parsed.json ]; then
        COORDINATE_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/kml_parsed.json')).get('coordinate_count', 0))" 2>/dev/null || echo "0")
        FIRST_COORD_LAT=$(python3 -c "import json; print(json.load(open('/tmp/kml_parsed.json')).get('first_coord', {}).get('lat', 0))" 2>/dev/null || echo "0")
        FIRST_COORD_LON=$(python3 -c "import json; print(json.load(open('/tmp/kml_parsed.json')).get('first_coord', {}).get('lon', 0))" 2>/dev/null || echo "0")
        LAST_COORD_LAT=$(python3 -c "import json; print(json.load(open('/tmp/kml_parsed.json')).get('last_coord', {}).get('lat', 0))" 2>/dev/null || echo "0")
        LAST_COORD_LON=$(python3 -c "import json; print(json.load(open('/tmp/kml_parsed.json')).get('last_coord', {}).get('lon', 0))" 2>/dev/null || echo "0")
        PATH_NAME=$(python3 -c "import json; print(json.load(open('/tmp/kml_parsed.json')).get('path_name', ''))" 2>/dev/null || echo "")
        ALL_COORDINATES=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/kml_parsed.json')).get('all_coordinates', [])))" 2>/dev/null || echo "[]")
        echo "Parsed: $COORDINATE_COUNT coordinates"
    fi
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "kml_exists": $KML_EXISTS,
    "kml_path": "$ACTUAL_PATH",
    "kml_size_bytes": $KML_SIZE,
    "kml_mtime": $KML_MTIME,
    "kml_created_during_task": $KML_CREATED_DURING_TASK,
    "kml_modified_during_task": $KML_MODIFIED_DURING_TASK,
    "coordinate_count": $COORDINATE_COUNT,
    "first_coord_lat": $FIRST_COORD_LAT,
    "first_coord_lon": $FIRST_COORD_LON,
    "last_coord_lat": $LAST_COORD_LAT,
    "last_coord_lon": $LAST_COORD_LON,
    "path_name": "$PATH_NAME",
    "all_coordinates": $ALL_COORDINATES,
    "google_earth_running": $GE_RUNNING,
    "google_earth_window": "$GE_WINDOW_TITLE",
    "final_screenshot": "/tmp/task_final_screenshot.png"
}
EOF

# Copy to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json