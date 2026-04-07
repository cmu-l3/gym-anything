#!/bin/bash
set -e
echo "=== Exporting lat_landfall_marking task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ELAPSED=$((TASK_END - TASK_START))
echo "Task duration: ${ELAPSED} seconds"

# Take final screenshot BEFORE any other operations
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Find and export myplaces.kml
MYPLACES_PATHS=(
    "/home/ga/.googleearth/myplaces.kml"
    "/home/ga/.config/Google/googleearth/myplaces.kml"
)

MYPLACES_FOUND="false"
MYPLACES_PATH=""
MYPLACES_CONTENT=""
CURRENT_PLACEMARK_COUNT=0
MYPLACES_MODIFIED="false"

for KML_PATH in "${MYPLACES_PATHS[@]}"; do
    if [ -f "$KML_PATH" ]; then
        MYPLACES_FOUND="true"
        MYPLACES_PATH="$KML_PATH"
        
        # Copy to accessible location
        cp "$KML_PATH" /tmp/myplaces_export.kml 2>/dev/null || true
        chmod 644 /tmp/myplaces_export.kml 2>/dev/null || true
        
        # Count placemarks
        CURRENT_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$KML_PATH" 2>/dev/null || echo "0")
        
        # Check if modified during task
        CURRENT_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")
        INITIAL_MTIME=$(cat /tmp/myplaces_initial_mtime.txt 2>/dev/null || echo "0")
        if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$INITIAL_MTIME" != "0" ]; then
            MYPLACES_MODIFIED="true"
        fi
        
        echo "Found myplaces.kml at $KML_PATH"
        echo "Current placemark count: $CURRENT_PLACEMARK_COUNT"
        echo "Modified during task: $MYPLACES_MODIFIED"
        break
    fi
done

# Get initial count for comparison
INITIAL_PLACEMARK_COUNT=$(cat /tmp/initial_placemark_count.txt 2>/dev/null || echo "0")
NEW_PLACEMARKS=$((CURRENT_PLACEMARK_COUNT - INITIAL_PLACEMARK_COUNT))
echo "New placemarks created: $NEW_PLACEMARKS"

# Check for target placemark and extract its data
TARGET_FOUND="false"
TARGET_NAME=""
TARGET_LATITUDE=""
TARGET_LONGITUDE=""
TARGET_DESCRIPTION=""

if [ -f /tmp/myplaces_export.kml ]; then
    # Use Python to parse KML and extract placemark data
    python3 << 'PYEOF' > /tmp/placemark_data.json 2>/dev/null || echo '{"error": "parse_failed"}' > /tmp/placemark_data.json
import xml.etree.ElementTree as ET
import json
import re

def parse_kml():
    result = {
        "placemarks": [],
        "target_found": False,
        "target_data": None
    }
    
    try:
        tree = ET.parse('/tmp/myplaces_export.kml')
        root = tree.getroot()
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Find all placemarks
        for pm in root.iter('{http://www.opengis.net/kml/2.2}Placemark'):
            pm_data = {}
            
            # Get name
            name_elem = pm.find('{http://www.opengis.net/kml/2.2}name')
            pm_data['name'] = name_elem.text if name_elem is not None and name_elem.text else ""
            
            # Get description
            desc_elem = pm.find('{http://www.opengis.net/kml/2.2}description')
            pm_data['description'] = desc_elem.text if desc_elem is not None and desc_elem.text else ""
            
            # Get coordinates from Point
            point = pm.find('{http://www.opengis.net/kml/2.2}Point')
            if point is not None:
                coords_elem = point.find('{http://www.opengis.net/kml/2.2}coordinates')
                if coords_elem is not None and coords_elem.text:
                    coords = coords_elem.text.strip().split(',')
                    if len(coords) >= 2:
                        pm_data['longitude'] = float(coords[0])
                        pm_data['latitude'] = float(coords[1])
            
            # Also check LookAt
            if 'latitude' not in pm_data:
                lookat = pm.find('{http://www.opengis.net/kml/2.2}LookAt')
                if lookat is not None:
                    lon = lookat.find('{http://www.opengis.net/kml/2.2}longitude')
                    lat = lookat.find('{http://www.opengis.net/kml/2.2}latitude')
                    if lon is not None and lat is not None:
                        pm_data['longitude'] = float(lon.text)
                        pm_data['latitude'] = float(lat.text)
            
            result['placemarks'].append(pm_data)
            
            # Check if this is our target placemark
            name_lower = pm_data.get('name', '').lower()
            if ('45n' in name_lower or '45°n' in name_lower or '45 n' in name_lower) and 'landfall' in name_lower:
                result['target_found'] = True
                result['target_data'] = pm_data
        
        # Fallback: check for any placemark near 45N if target not found by name
        if not result['target_found']:
            for pm_data in result['placemarks']:
                lat = pm_data.get('latitude', 0)
                if lat and abs(lat - 45.0) < 0.1:
                    result['target_data'] = pm_data
                    result['near_target'] = True
                    break
    
    except Exception as e:
        result['error'] = str(e)
    
    print(json.dumps(result))

parse_kml()
PYEOF
fi

# Read parsed data
if [ -f /tmp/placemark_data.json ]; then
    TARGET_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/placemark_data.json')); print('true' if d.get('target_found') or d.get('near_target') else 'false')" 2>/dev/null || echo "false")
    
    if [ "$TARGET_FOUND" = "true" ]; then
        TARGET_DATA=$(python3 -c "import json; d=json.load(open('/tmp/placemark_data.json')); t=d.get('target_data',{}); print(json.dumps(t))" 2>/dev/null || echo "{}")
        TARGET_NAME=$(echo "$TARGET_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || echo "")
        TARGET_LATITUDE=$(echo "$TARGET_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('latitude',''))" 2>/dev/null || echo "")
        TARGET_LONGITUDE=$(echo "$TARGET_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('longitude',''))" 2>/dev/null || echo "")
        TARGET_DESCRIPTION=$(echo "$TARGET_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))" 2>/dev/null || echo "")
    fi
fi

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window title
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $ELAPSED,
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "myplaces_found": $MYPLACES_FOUND,
    "myplaces_path": "$MYPLACES_PATH",
    "myplaces_modified": $MYPLACES_MODIFIED,
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "current_placemark_count": $CURRENT_PLACEMARK_COUNT,
    "new_placemarks_created": $NEW_PLACEMARKS,
    "target_placemark_found": $TARGET_FOUND,
    "target_name": "$TARGET_NAME",
    "target_latitude": "$TARGET_LATITUDE",
    "target_longitude": "$TARGET_LONGITUDE",
    "target_description": "$TARGET_DESCRIPTION",
    "screenshot_path": "/tmp/task_final_state.png",
    "kml_export_path": "/tmp/myplaces_export.kml",
    "placemark_data_path": "/tmp/placemark_data.json"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result Summary ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="