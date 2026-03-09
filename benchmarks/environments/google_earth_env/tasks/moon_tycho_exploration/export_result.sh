#!/bin/bash
set -e
echo "=== Exporting Moon Tycho Exploration results ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot before any other operations
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
else
    echo "WARNING: Could not capture final screenshot"
fi

# ============================================================
# Check myplaces.kml for Tycho placemark
# ============================================================
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"

MYPLACES_EXISTS="false"
MYPLACES_MODIFIED="false"
MYPLACES_MTIME="0"
MYPLACES_SIZE="0"
TYCHO_FOUND="false"
TYCHO_NAME=""
TYCHO_DESCRIPTION=""
TYCHO_COORDINATES=""
HAS_85KM="false"

if [ -f "$MYPLACES_FILE" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES_FILE" 2>/dev/null || echo "0")
    
    # Check if file was modified during task
    INITIAL_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('myplaces_mtime', 0))" 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$INITIAL_MTIME" ] && [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_MODIFIED="true"
    fi
    
    # Search for Tycho placemark
    if grep -qi "tycho" "$MYPLACES_FILE" 2>/dev/null; then
        TYCHO_FOUND="true"
        
        # Extract placemark details using Python for reliable XML parsing
        PLACEMARK_INFO=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import re

try:
    tree = ET.parse("/home/ga/.googleearth/myplaces.kml")
    root = tree.getroot()
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    result = {
        "found": False,
        "name": "",
        "description": "",
        "coordinates": "",
        "latitude": None,
        "longitude": None,
        "has_85km": False
    }
    
    # Find all placemarks
    placemarks = root.findall('.//kml:Placemark', ns)
    if not placemarks:
        placemarks = root.findall('.//{http://www.opengis.net/kml/2.2}Placemark')
    if not placemarks:
        placemarks = root.findall('.//Placemark')
    
    for pm in placemarks:
        # Get name
        name_elem = pm.find('kml:name', ns)
        if name_elem is None:
            name_elem = pm.find('{http://www.opengis.net/kml/2.2}name')
        if name_elem is None:
            name_elem = pm.find('name')
        
        name = name_elem.text if name_elem is not None and name_elem.text else ""
        
        if 'tycho' in name.lower():
            result["found"] = True
            result["name"] = name
            
            # Get description
            desc_elem = pm.find('kml:description', ns)
            if desc_elem is None:
                desc_elem = pm.find('{http://www.opengis.net/kml/2.2}description')
            if desc_elem is None:
                desc_elem = pm.find('description')
            
            if desc_elem is not None and desc_elem.text:
                result["description"] = desc_elem.text[:200]
                if '85' in desc_elem.text:
                    result["has_85km"] = True
            
            # Get coordinates
            coords_elem = pm.find('.//kml:coordinates', ns)
            if coords_elem is None:
                coords_elem = pm.find('.//{http://www.opengis.net/kml/2.2}coordinates')
            if coords_elem is None:
                coords_elem = pm.find('.//coordinates')
            
            if coords_elem is not None and coords_elem.text:
                coords = coords_elem.text.strip()
                result["coordinates"] = coords
                parts = coords.split(',')
                if len(parts) >= 2:
                    try:
                        result["longitude"] = float(parts[0])
                        result["latitude"] = float(parts[1])
                    except:
                        pass
            
            break
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"found": False, "error": str(e)}))
PYEOF
)
        
        echo "Placemark info: $PLACEMARK_INFO"
        
        # Parse the Python output
        TYCHO_NAME=$(echo "$PLACEMARK_INFO" | python3 -c "import json, sys; print(json.load(sys.stdin).get('name', ''))" 2>/dev/null || echo "")
        TYCHO_DESCRIPTION=$(echo "$PLACEMARK_INFO" | python3 -c "import json, sys; print(json.load(sys.stdin).get('description', ''))" 2>/dev/null || echo "")
        TYCHO_COORDINATES=$(echo "$PLACEMARK_INFO" | python3 -c "import json, sys; print(json.load(sys.stdin).get('coordinates', ''))" 2>/dev/null || echo "")
        TYCHO_LAT=$(echo "$PLACEMARK_INFO" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('latitude') if d.get('latitude') is not None else 'null')" 2>/dev/null || echo "null")
        TYCHO_LON=$(echo "$PLACEMARK_INFO" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('longitude') if d.get('longitude') is not None else 'null')" 2>/dev/null || echo "null")
        HAS_85KM=$(echo "$PLACEMARK_INFO" | python3 -c "import json, sys; print('true' if json.load(sys.stdin).get('has_85km') else 'false')" 2>/dev/null || echo "false")
    fi
fi

# ============================================================
# Check window state for Moon mode evidence
# ============================================================
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
ALL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
GE_WINDOW=$(echo "$ALL_WINDOWS" | grep -i "Google Earth" | head -1 || echo "")

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# ============================================================
# Create comprehensive result JSON
# ============================================================
RESULT_FILE="/tmp/task_result.json"

cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "google_earth_running": $GE_RUNNING,
    "window_title": "$(echo "$WINDOW_TITLE" | sed 's/"/\\"/g')",
    "ge_window_info": "$(echo "$GE_WINDOW" | sed 's/"/\\"/g')",
    "myplaces": {
        "exists": $MYPLACES_EXISTS,
        "modified_during_task": $MYPLACES_MODIFIED,
        "mtime": $MYPLACES_MTIME,
        "size_bytes": $MYPLACES_SIZE
    },
    "tycho_placemark": {
        "found": $TYCHO_FOUND,
        "name": "$(echo "$TYCHO_NAME" | sed 's/"/\\"/g')",
        "description": "$(echo "$TYCHO_DESCRIPTION" | sed 's/"/\\"/g' | tr '\n' ' ')",
        "coordinates": "$TYCHO_COORDINATES",
        "latitude": $TYCHO_LAT,
        "longitude": $TYCHO_LON,
        "has_85km_reference": $HAS_85KM
    },
    "screenshots": {
        "initial": "/tmp/task_initial_state.png",
        "final": "/tmp/task_final.png"
    }
}
EOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo ""
echo "=== Export complete ==="
echo "Result saved to: $RESULT_FILE"
cat "$RESULT_FILE"