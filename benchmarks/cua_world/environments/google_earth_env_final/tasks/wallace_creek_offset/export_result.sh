#!/bin/bash
echo "=== Exporting Wallace Creek Fault Offset task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# Check KML file
KML_PATH="/home/ga/Documents/wallace_creek_offset.kml"
KML_EXISTS="false"
KML_SIZE="0"
KML_MTIME="0"
KML_CREATED_DURING_TASK="false"
KML_CONTENT=""
PLACEMARK_NAME=""
PLACEMARK_DESCRIPTION=""
PLACEMARK_LAT="0"
PLACEMARK_LON="0"
MEASUREMENT_VALUE=""

if [ -f "$KML_PATH" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c %s "$KML_PATH" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$KML_MTIME" -gt "$TASK_START" ]; then
        KML_CREATED_DURING_TASK="true"
        echo "KML file was created during task execution"
    else
        echo "WARNING: KML file exists but was not created during task"
    fi
    
    # Read KML content for parsing
    KML_CONTENT=$(cat "$KML_PATH" 2>/dev/null || echo "")
    
    # Parse KML using Python for reliability
    PARSED_KML=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import re
import sys

kml_path = "/home/ga/Documents/wallace_creek_offset.kml"
result = {
    "parse_success": False,
    "placemark_name": "",
    "placemark_description": "",
    "placemark_lat": 0,
    "placemark_lon": 0,
    "measurement_value": None
}

try:
    tree = ET.parse(kml_path)
    root = tree.getroot()
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Find placemarks (try with and without namespace)
    placemarks = root.findall('.//kml:Placemark', ns)
    if not placemarks:
        placemarks = root.findall('.//Placemark')
    
    for pm in placemarks:
        # Get name
        name_elem = pm.find('kml:name', ns) or pm.find('name')
        if name_elem is not None and name_elem.text:
            result["placemark_name"] = name_elem.text
        
        # Get description
        desc_elem = pm.find('kml:description', ns) or pm.find('description')
        if desc_elem is not None and desc_elem.text:
            result["placemark_description"] = desc_elem.text
            
            # Try to extract measurement value from description
            desc_text = desc_elem.text
            patterns = [
                r'(\d+(?:\.\d+)?)\s*(?:m|meters?|metres?)\b',
                r'offset[:\s]+(\d+(?:\.\d+)?)',
                r'measured?[:\s]+(\d+(?:\.\d+)?)',
                r'measurement[:\s]+(\d+(?:\.\d+)?)',
            ]
            for pattern in patterns:
                match = re.search(pattern, desc_text, re.IGNORECASE)
                if match:
                    try:
                        val = float(match.group(1))
                        if 50 <= val <= 500:  # Sanity check range
                            result["measurement_value"] = val
                            break
                    except:
                        pass
        
        # Get coordinates
        coord_elem = pm.find('.//kml:coordinates', ns) or pm.find('.//coordinates')
        if coord_elem is not None and coord_elem.text:
            coords = coord_elem.text.strip()
            parts = coords.split(',')
            if len(parts) >= 2:
                try:
                    result["placemark_lon"] = float(parts[0])
                    result["placemark_lat"] = float(parts[1])
                except:
                    pass
        
        # Only process first placemark that has a name matching our target
        if "wallace" in result["placemark_name"].lower() or "offset" in result["placemark_name"].lower():
            break
    
    result["parse_success"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)
    
    # Extract parsed values
    if [ -n "$PARSED_KML" ]; then
        PARSE_SUCCESS=$(echo "$PARSED_KML" | python3 -c "import json,sys; print(json.load(sys.stdin).get('parse_success', False))" 2>/dev/null || echo "false")
        PLACEMARK_NAME=$(echo "$PARSED_KML" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_name', ''))" 2>/dev/null || echo "")
        PLACEMARK_DESCRIPTION=$(echo "$PARSED_KML" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_description', ''))" 2>/dev/null || echo "")
        PLACEMARK_LAT=$(echo "$PARSED_KML" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_lat', 0))" 2>/dev/null || echo "0")
        PLACEMARK_LON=$(echo "$PARSED_KML" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_lon', 0))" 2>/dev/null || echo "0")
        MEASUREMENT_VALUE=$(echo "$PARSED_KML" | python3 -c "import json,sys; v=json.load(sys.stdin).get('measurement_value'); print(v if v is not None else 'null')" 2>/dev/null || echo "null")
        
        echo "Parsed KML:"
        echo "  Name: $PLACEMARK_NAME"
        echo "  Lat: $PLACEMARK_LAT"
        echo "  Lon: $PLACEMARK_LON"
        echo "  Measurement: $MEASUREMENT_VALUE"
    fi
else
    echo "KML file not found at $KML_PATH"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window information
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
GE_WINDOW_EXISTS="false"
if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
    GE_WINDOW_EXISTS="true"
fi

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "kml_exists": $KML_EXISTS,
    "kml_size_bytes": $KML_SIZE,
    "kml_mtime": $KML_MTIME,
    "kml_created_during_task": $KML_CREATED_DURING_TASK,
    "kml_parse_success": ${PARSE_SUCCESS:-false},
    "placemark_name": "$PLACEMARK_NAME",
    "placemark_description": "$(echo "$PLACEMARK_DESCRIPTION" | tr '\n' ' ' | sed 's/"/\\"/g')",
    "placemark_lat": $PLACEMARK_LAT,
    "placemark_lon": $PLACEMARK_LON,
    "measurement_value": $MEASUREMENT_VALUE,
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_exists": $GE_WINDOW_EXISTS,
    "active_window_title": "$WINDOW_TITLE",
    "final_screenshot_path": "/tmp/task_final.png",
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json