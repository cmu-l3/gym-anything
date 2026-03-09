#!/bin/bash
set -e
echo "=== Exporting location_disambiguation task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any analysis
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
fi

# Check for the expected output KML file
OUTPUT_PATH="/home/ga/Documents/cambridge_research.kml"
KML_EXISTS="false"
KML_SIZE="0"
KML_MTIME="0"
FILE_CREATED_DURING_TASK="false"
KML_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task window
    if [ "$KML_MTIME" -gt "$TASK_START" ] && [ "$KML_MTIME" -le "$TASK_END" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task"
    else
        echo "WARNING: KML file modification time outside task window"
    fi
    
    # Read KML content for verification
    KML_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null | head -c 50000 || echo "")
    echo "KML file found: $KML_SIZE bytes"
else
    echo "KML file NOT found at $OUTPUT_PATH"
    
    # Check for any KML files in Documents
    echo "Checking for other KML files..."
    ls -la /home/ga/Documents/*.kml 2>/dev/null || echo "No KML files found"
fi

# Check Google Earth window state
GE_RUNNING="false"
GE_WINDOW_TITLE=""
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi

# Check My Places for any new placemarks
MYPLACES_CONTENT=""
if [ -f /home/ga/.googleearth/myplaces.kml ]; then
    MYPLACES_CONTENT=$(cat /home/ga/.googleearth/myplaces.kml 2>/dev/null | head -c 20000 || echo "")
fi

# Parse KML file to extract coordinates if it exists
PLACEMARK_NAME=""
PLACEMARK_LON=""
PLACEMARK_LAT=""
PLACEMARK_DESCRIPTION=""
COORDS_IN_DESCRIPTION="false"

if [ "$KML_EXISTS" = "true" ] && [ -n "$KML_CONTENT" ]; then
    # Use Python to parse KML
    PARSED_DATA=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import sys
import re

try:
    tree = ET.parse("/home/ga/Documents/cambridge_research.kml")
    root = tree.getroot()
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Try with namespace first, then without
    placemark = root.find('.//{http://www.opengis.net/kml/2.2}Placemark')
    if placemark is None:
        placemark = root.find('.//Placemark')
    
    result = {
        "parse_success": True,
        "placemark_found": placemark is not None,
        "name": "",
        "description": "",
        "longitude": 0,
        "latitude": 0,
        "coords_in_desc": False
    }
    
    if placemark is not None:
        # Get name
        name_elem = placemark.find('{http://www.opengis.net/kml/2.2}name')
        if name_elem is None:
            name_elem = placemark.find('name')
        if name_elem is not None and name_elem.text:
            result["name"] = name_elem.text
        
        # Get description
        desc_elem = placemark.find('{http://www.opengis.net/kml/2.2}description')
        if desc_elem is None:
            desc_elem = placemark.find('description')
        if desc_elem is not None and desc_elem.text:
            result["description"] = desc_elem.text
            # Check for coordinates in description
            if re.search(r'[Cc]oordinates?\s*:?\s*-?\d+\.?\d*', desc_elem.text):
                result["coords_in_desc"] = True
        
        # Get coordinates
        coords_elem = placemark.find('.//{http://www.opengis.net/kml/2.2}coordinates')
        if coords_elem is None:
            coords_elem = placemark.find('.//coordinates')
        if coords_elem is not None and coords_elem.text:
            parts = coords_elem.text.strip().split(',')
            if len(parts) >= 2:
                result["longitude"] = float(parts[0])
                result["latitude"] = float(parts[1])
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"parse_success": False, "error": str(e)}))
PYEOF
)
    
    if [ -n "$PARSED_DATA" ]; then
        PLACEMARK_NAME=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || echo "")
        PLACEMARK_LON=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('longitude',0))" 2>/dev/null || echo "0")
        PLACEMARK_LAT=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('latitude',0))" 2>/dev/null || echo "0")
        PLACEMARK_DESCRIPTION=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))" 2>/dev/null || echo "")
        COORDS_IN_DESCRIPTION=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('coords_in_desc',False) else 'false')" 2>/dev/null || echo "false")
        
        echo "Parsed placemark: name='$PLACEMARK_NAME', lat=$PLACEMARK_LAT, lon=$PLACEMARK_LON"
    fi
fi

# Create comprehensive JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "kml_file": {
        "exists": $KML_EXISTS,
        "path": "$OUTPUT_PATH",
        "size_bytes": $KML_SIZE,
        "mtime": $KML_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK
    },
    "placemark": {
        "name": "$PLACEMARK_NAME",
        "latitude": $PLACEMARK_LAT,
        "longitude": $PLACEMARK_LON,
        "description": $(python3 -c "import json; print(json.dumps('$PLACEMARK_DESCRIPTION'))" 2>/dev/null || echo '""'),
        "coords_in_description": $COORDS_IN_DESCRIPTION
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE"
    },
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "path": "/tmp/task_final.png",
        "size_bytes": $SCREENSHOT_SIZE
    },
    "kml_content_preview": $(python3 -c "import json; print(json.dumps('${KML_CONTENT:0:2000}'))" 2>/dev/null || echo '""')
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results Summary ==="
echo "KML file exists: $KML_EXISTS"
echo "Created during task: $FILE_CREATED_DURING_TASK"
echo "Placemark name: $PLACEMARK_NAME"
echo "Coordinates: $PLACEMARK_LAT, $PLACEMARK_LON"
echo "Coords in description: $COORDS_IN_DESCRIPTION"
echo ""
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="