#!/bin/bash
set -e
echo "=== Exporting Alcatraz Boundary Export task result ==="

export DISPLAY=${DISPLAY:-:1}

# Take final screenshot BEFORE any other operations
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"

# ================================================================
# Check expected output file
# ================================================================
OUTPUT_PATH="/home/ga/Documents/alcatraz_boundary.kml"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task execution"
    else
        echo "WARNING: KML file existed before task started"
    fi
    
    echo "Output file found: $OUTPUT_PATH ($OUTPUT_SIZE bytes)"
else
    echo "Output file NOT found at $OUTPUT_PATH"
    
    # Check for alternative filenames
    echo "Checking for alternative KML files..."
    ls -la /home/ga/Documents/*.kml 2>/dev/null || echo "No KML files in Documents"
fi

# ================================================================
# Check for any KML files that might be the output
# ================================================================
KML_FILES_FOUND=""
KML_COUNT=0
for kml in /home/ga/Documents/*.kml; do
    if [ -f "$kml" ]; then
        KML_COUNT=$((KML_COUNT + 1))
        KML_FILES_FOUND="$KML_FILES_FOUND $kml"
        echo "Found KML file: $kml"
    fi
done

# ================================================================
# Check Google Earth running state
# ================================================================
GE_RUNNING="false"
if pgrep -f google-earth > /dev/null 2>&1; then
    GE_RUNNING="true"
    echo "Google Earth is running"
fi

# Get window info
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
WINDOW_LIST=$(wmctrl -l 2>/dev/null || echo "")

# ================================================================
# Parse KML file content if it exists
# ================================================================
KML_VALID="false"
KML_HAS_POLYGON="false"
KML_COORD_COUNT="0"
KML_PLACEMARK_NAME=""
KML_COORDINATES=""

if [ -f "$OUTPUT_PATH" ]; then
    # Check if it's valid XML/KML
    if python3 -c "import xml.etree.ElementTree as ET; ET.parse('$OUTPUT_PATH')" 2>/dev/null; then
        KML_VALID="true"
        echo "KML file is valid XML"
        
        # Extract polygon info using Python
        PARSED_INFO=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json

try:
    tree = ET.parse('/home/ga/Documents/alcatraz_boundary.kml')
    root = tree.getroot()
    
    # Define namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Try to find coordinates with and without namespace
    coords_elem = None
    for path in ['.//kml:coordinates', './/{http://www.opengis.net/kml/2.2}coordinates', './/coordinates']:
        coords_elem = root.find(path, ns) if 'kml:' in path else root.find(path)
        if coords_elem is not None:
            break
    
    # Try to find name
    name_elem = None
    for path in ['.//kml:name', './/{http://www.opengis.net/kml/2.2}name', './/name']:
        name_elem = root.find(path, ns) if 'kml:' in path else root.find(path)
        if name_elem is not None and name_elem.text:
            break
    
    result = {
        "has_polygon": coords_elem is not None,
        "coordinates": coords_elem.text.strip() if coords_elem is not None and coords_elem.text else "",
        "coord_count": 0,
        "placemark_name": name_elem.text.strip() if name_elem is not None and name_elem.text else ""
    }
    
    if coords_elem is not None and coords_elem.text:
        coords_text = coords_elem.text.strip()
        coord_pairs = [c for c in coords_text.split() if ',' in c]
        result["coord_count"] = len(coord_pairs)
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e), "has_polygon": False, "coordinates": "", "coord_count": 0, "placemark_name": ""}))
PYEOF
)
        
        KML_HAS_POLYGON=$(echo "$PARSED_INFO" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('has_polygon') else 'false')" 2>/dev/null || echo "false")
        KML_COORD_COUNT=$(echo "$PARSED_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('coord_count', 0))" 2>/dev/null || echo "0")
        KML_PLACEMARK_NAME=$(echo "$PARSED_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_name', ''))" 2>/dev/null || echo "")
        KML_COORDINATES=$(echo "$PARSED_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('coordinates', ''))" 2>/dev/null || echo "")
        
        echo "KML has polygon: $KML_HAS_POLYGON"
        echo "Coordinate count: $KML_COORD_COUNT"
        echo "Placemark name: $KML_PLACEMARK_NAME"
    else
        echo "WARNING: KML file is not valid XML"
    fi
fi

# ================================================================
# Create JSON result file
# ================================================================
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_path": "$OUTPUT_PATH",
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "kml_valid": $KML_VALID,
    "kml_has_polygon": $KML_HAS_POLYGON,
    "kml_coord_count": $KML_COORD_COUNT,
    "kml_placemark_name": "$KML_PLACEMARK_NAME",
    "kml_coordinates": "$KML_COORDINATES",
    "kml_files_count": $KML_COUNT,
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="