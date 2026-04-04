#!/bin/bash
set -e
echo "=== Exporting Bridge Site Selection task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# Find myplaces.kml
MYPLACES_PATH=""
if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
elif [ -f "/home/ga/.config/Google/GoogleEarthPro/myplaces.kml" ]; then
    MYPLACES_PATH="/home/ga/.config/Google/GoogleEarthPro/myplaces.kml"
fi

# Initialize variables
PLACEMARK_FOUND="false"
PLACEMARK_NAME=""
PLACEMARK_DESCRIPTION=""
PLACEMARK_LAT=""
PLACEMARK_LON=""
MEASUREMENT_VALUE=""
FINAL_PLACEMARK_COUNT="0"
FILE_MODIFIED_DURING_TASK="false"

if [ -n "$MYPLACES_PATH" ] && [ -f "$MYPLACES_PATH" ]; then
    echo "Found myplaces.kml at: $MYPLACES_PATH"
    
    # Count final placemarks
    FINAL_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_PATH" 2>/dev/null || echo "0")
    
    # Check if file was modified during task
    FILE_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    # Copy myplaces.kml for verification
    cp "$MYPLACES_PATH" /tmp/myplaces_final.kml 2>/dev/null || true
    
    # Extract placemark data using Python for reliable XML parsing
    python3 << 'PYEOF' > /tmp/placemark_data.json 2>/dev/null || echo '{"error": "parsing failed"}' > /tmp/placemark_data.json
import re
import json
from xml.etree import ElementTree as ET

def extract_placemarks(kml_path):
    placemarks = []
    try:
        with open(kml_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # Handle KML namespace
        content = re.sub(r'\sxmlns="[^"]+"', '', content, count=1)
        root = ET.fromstring(content)
        
        for pm in root.iter('Placemark'):
            name_elem = pm.find('.//name')
            desc_elem = pm.find('.//description')
            coord_elem = pm.find('.//coordinates')
            
            if name_elem is not None:
                placemark = {
                    'name': name_elem.text or '',
                    'description': desc_elem.text if desc_elem is not None else '',
                    'coordinates': None
                }
                
                if coord_elem is not None and coord_elem.text:
                    coords = coord_elem.text.strip().split(',')
                    if len(coords) >= 2:
                        try:
                            placemark['coordinates'] = {
                                'lon': float(coords[0]),
                                'lat': float(coords[1])
                            }
                        except ValueError:
                            pass
                
                placemarks.append(placemark)
    except Exception as e:
        return {'error': str(e), 'placemarks': []}
    
    return {'placemarks': placemarks, 'error': None}

result = extract_placemarks('/tmp/myplaces_final.kml')
print(json.dumps(result, indent=2))
PYEOF

    # Extract target placemark info
    if [ -f /tmp/placemark_data.json ]; then
        PLACEMARK_INFO=$(python3 << 'PYEOF' 2>/dev/null || echo '{}')
import json
import re

with open('/tmp/placemark_data.json', 'r') as f:
    data = json.load(f)

target = None
for pm in data.get('placemarks', []):
    name = pm.get('name', '').lower().replace(' ', '_').replace('-', '_')
    if 'bridge' in name and ('site' in name or 'recommendation' in name):
        target = pm
        break
    elif 'bridge_site_recommendation' in name:
        target = pm
        break

if target:
    desc = target.get('description', '') or ''
    # Extract measurement from description
    measurement = None
    patterns = [
        r'(\d+(?:,\d{3})*(?:\.\d+)?)\s*(?:m|meters?)\b',
        r'width[:\s]*(\d+(?:,\d{3})*(?:\.\d+)?)',
        r'(\d{3,4})\s*m\b'
    ]
    for pattern in patterns:
        match = re.search(pattern, desc, re.IGNORECASE)
        if match:
            measurement = float(match.group(1).replace(',', ''))
            break
    
    result = {
        'found': True,
        'name': target.get('name', ''),
        'description': desc,
        'lat': target.get('coordinates', {}).get('lat') if target.get('coordinates') else None,
        'lon': target.get('coordinates', {}).get('lon') if target.get('coordinates') else None,
        'measurement': measurement
    }
else:
    result = {'found': False}

print(json.dumps(result))
PYEOF
        )
        
        PLACEMARK_FOUND=$(echo "$PLACEMARK_INFO" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('found', False)).lower())" 2>/dev/null || echo "false")
        if [ "$PLACEMARK_FOUND" = "true" ]; then
            PLACEMARK_NAME=$(echo "$PLACEMARK_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name', ''))" 2>/dev/null || echo "")
            PLACEMARK_DESCRIPTION=$(echo "$PLACEMARK_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description', ''))" 2>/dev/null || echo "")
            PLACEMARK_LAT=$(echo "$PLACEMARK_INFO" | python3 -c "import json,sys; v=json.load(sys.stdin).get('lat'); print(v if v else '')" 2>/dev/null || echo "")
            PLACEMARK_LON=$(echo "$PLACEMARK_INFO" | python3 -c "import json,sys; v=json.load(sys.stdin).get('lon'); print(v if v else '')" 2>/dev/null || echo "")
            MEASUREMENT_VALUE=$(echo "$PLACEMARK_INFO" | python3 -c "import json,sys; v=json.load(sys.stdin).get('measurement'); print(v if v else '')" 2>/dev/null || echo "")
        fi
    fi
else
    echo "WARNING: myplaces.kml not found"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window information
WINDOW_INFO=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "google earth" | head -1 || echo "")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "google_earth_running": $GE_RUNNING,
    "myplaces_path": "$MYPLACES_PATH",
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "initial_placemark_count": $(cat /tmp/initial_placemark_count.txt 2>/dev/null || echo "0"),
    "final_placemark_count": $FINAL_PLACEMARK_COUNT,
    "placemark_found": $PLACEMARK_FOUND,
    "placemark_name": "$PLACEMARK_NAME",
    "placemark_description": "$PLACEMARK_DESCRIPTION",
    "placemark_lat": $([[ -n "$PLACEMARK_LAT" ]] && echo "$PLACEMARK_LAT" || echo "null"),
    "placemark_lon": $([[ -n "$PLACEMARK_LON" ]] && echo "$PLACEMARK_LON" || echo "null"),
    "measurement_value": $([[ -n "$MEASUREMENT_VALUE" ]] && echo "$MEASUREMENT_VALUE" || echo "null"),
    "final_screenshot": "/tmp/task_final_state.png",
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE,
    "window_info": "$WINDOW_INFO"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="