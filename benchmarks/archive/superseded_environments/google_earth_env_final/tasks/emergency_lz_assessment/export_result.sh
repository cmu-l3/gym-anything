#!/bin/bash
set -e
echo "=== Exporting Emergency LZ Assessment Result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task end time: $TASK_END"
echo "Task start time: $TASK_START"
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# ================================================================
# CAPTURE FINAL SCREENSHOT
# ================================================================
echo "Capturing final state screenshot..."
scrot /tmp/task_final_state.png 2>/dev/null || \
    import -window root /tmp/task_final_state.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE="0"
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
fi

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_PATH="/home/ga/Documents/emergency_lz_assessment.kml"

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
        echo "KML file was created during task session"
    else
        echo "WARNING: KML file predates task start"
    fi
    echo "Output file exists: $OUTPUT_SIZE bytes"
else
    echo "Output file NOT found at $OUTPUT_PATH"
fi

# ================================================================
# PARSE KML FILE IF IT EXISTS
# ================================================================
PLACEMARK_COUNT="0"
HAS_FOLDER="false"
FOLDER_NAME=""
COORDINATES_JSON="[]"
PLACEMARK_NAMES_JSON="[]"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Parsing KML file..."
    
    # Check for folder structure
    if grep -qi "<Folder>" "$OUTPUT_PATH" 2>/dev/null; then
        HAS_FOLDER="true"
        # Try to extract folder name
        FOLDER_NAME=$(grep -oP '(?<=<name>)[^<]+(?=</name>)' "$OUTPUT_PATH" 2>/dev/null | head -1 || echo "")
        echo "Folder found: $FOLDER_NAME"
    fi
    
    # Count placemarks
    PLACEMARK_COUNT=$(grep -c "<Placemark>" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    echo "Placemark count: $PLACEMARK_COUNT"
    
    # Extract coordinates and names using Python for reliable parsing
    PARSE_RESULT=$(python3 << 'PYEOF'
import re
import json

kml_path = "/home/ga/Documents/emergency_lz_assessment.kml"
try:
    with open(kml_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Extract placemarks with names and coordinates
    placemarks = []
    placemark_pattern = r'<Placemark>(.*?)</Placemark>'
    name_pattern = r'<name>([^<]+)</name>'
    desc_pattern = r'<description>([^<]*)</description>'
    coords_pattern = r'<coordinates>([^<]+)</coordinates>'
    
    for match in re.finditer(placemark_pattern, content, re.DOTALL):
        pm_content = match.group(1)
        name_match = re.search(name_pattern, pm_content)
        desc_match = re.search(desc_pattern, pm_content)
        coords_match = re.search(coords_pattern, pm_content)
        
        pm_data = {
            'name': name_match.group(1) if name_match else '',
            'description': desc_match.group(1) if desc_match else '',
            'coordinates': ''
        }
        
        if coords_match:
            coords_str = coords_match.group(1).strip()
            parts = coords_str.split(',')
            if len(parts) >= 2:
                try:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    alt = float(parts[2]) if len(parts) >= 3 else 0
                    pm_data['coordinates'] = f"{lat},{lon},{alt}"
                    pm_data['lat'] = lat
                    pm_data['lon'] = lon
                    pm_data['alt'] = alt
                except:
                    pass
        
        placemarks.append(pm_data)
    
    result = {
        'success': True,
        'placemarks': placemarks,
        'count': len(placemarks)
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'success': False, 'error': str(e), 'placemarks': [], 'count': 0}))
PYEOF
)
    
    echo "Parse result: $PARSE_RESULT"
    
    # Extract values from parse result
    PARSE_SUCCESS=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('success', False))" 2>/dev/null || echo "false")
    if [ "$PARSE_SUCCESS" = "True" ] || [ "$PARSE_SUCCESS" = "true" ]; then
        COORDINATES_JSON=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps([{'name':p.get('name',''),'lat':p.get('lat',0),'lon':p.get('lon',0),'alt':p.get('alt',0),'description':p.get('description','')} for p in d.get('placemarks',[])]))" 2>/dev/null || echo "[]")
        PLACEMARK_NAMES_JSON=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps([p.get('name','') for p in d.get('placemarks',[])]))" 2>/dev/null || echo "[]")
    fi
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOWS=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

echo "Google Earth running: $GE_RUNNING"
echo "Window title: $GE_WINDOW_TITLE"

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "placemark_count": $PLACEMARK_COUNT,
    "has_folder": $HAS_FOLDER,
    "folder_name": "$FOLDER_NAME",
    "placemarks": $COORDINATES_JSON,
    "placemark_names": $PLACEMARK_NAMES_JSON,
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size": $SCREENSHOT_SIZE,
    "output_path": "$OUTPUT_PATH"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also copy the KML file to /tmp for easy retrieval
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/emergency_lz_assessment.kml 2>/dev/null || true
    chmod 666 /tmp/emergency_lz_assessment.kml 2>/dev/null || true
fi

echo ""
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="