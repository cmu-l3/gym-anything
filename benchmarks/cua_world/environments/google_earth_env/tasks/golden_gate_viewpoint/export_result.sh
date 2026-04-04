#!/bin/bash
set -e
echo "=== Exporting Golden Gate Viewpoint task result ==="

export DISPLAY=${DISPLAY:-:1}

# ============================================================
# RECORD TIMESTAMPS
# ============================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# ============================================================
# CAPTURE FINAL SCREENSHOT
# ============================================================
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
fi

# ============================================================
# CHECK IF GOOGLE EARTH IS RUNNING
# ============================================================
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GOOGLE_EARTH_RUNNING="true"
    echo "Google Earth Pro is running"
else
    GOOGLE_EARTH_RUNNING="false"
    echo "WARNING: Google Earth Pro is not running"
fi

# ============================================================
# CHECK KML FILE FOR PLACEMARKS
# ============================================================
GOOGLEEARTH_DIR="/home/ga/.googleearth"
KML_FILE="$GOOGLEEARTH_DIR/myplaces.kml"

# Check if KML file exists and was modified
KML_EXISTS="false"
KML_MODIFIED="false"
KML_SIZE="0"
CURRENT_KML_HASH="none"

if [ -f "$KML_FILE" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c %s "$KML_FILE" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c %Y "$KML_FILE" 2>/dev/null || echo "0")
    CURRENT_KML_HASH=$(md5sum "$KML_FILE" 2>/dev/null | cut -d' ' -f1 || echo "none")
    INITIAL_KML_HASH=$(cat /tmp/initial_kml_hash.txt 2>/dev/null || echo "none")
    
    if [ "$CURRENT_KML_HASH" != "$INITIAL_KML_HASH" ]; then
        KML_MODIFIED="true"
        echo "KML file was modified during task"
    else
        echo "WARNING: KML file unchanged from initial state"
    fi
    
    if [ "$KML_MTIME" -gt "$TASK_START" ]; then
        KML_MODIFIED="true"
        echo "KML file modification time is after task start"
    fi
fi

# ============================================================
# PARSE KML FOR PLACEMARK DATA
# ============================================================
echo "Parsing KML for placemark data..."

# Use Python to parse KML and extract placemark info
PARSED_DATA=$(python3 << 'PYEOF'
import json
import re
from xml.etree import ElementTree as ET

kml_path = "/home/ga/.googleearth/myplaces.kml"
result = {
    "placemark_found": False,
    "placemark_name": "",
    "placemark_description": "",
    "has_lookat": False,
    "lookat": {
        "latitude": None,
        "longitude": None,
        "range": None,
        "tilt": None,
        "heading": None,
        "altitude": None
    },
    "parse_error": None
}

try:
    tree = ET.parse(kml_path)
    root = tree.getroot()
    
    # Handle KML namespace
    ns = {
        'kml': 'http://www.opengis.net/kml/2.2',
        'gx': 'http://www.google.com/kml/ext/2.2'
    }
    
    # Find all placemarks (try with and without namespace)
    placemarks = root.findall('.//{http://www.opengis.net/kml/2.2}Placemark')
    if not placemarks:
        placemarks = root.findall('.//Placemark')
    
    # Look for our specific placemark
    for pm in placemarks:
        # Get name
        name_elem = pm.find('{http://www.opengis.net/kml/2.2}name')
        if name_elem is None:
            name_elem = pm.find('name')
        
        name = name_elem.text if name_elem is not None and name_elem.text else ""
        
        # Check if this is our placemark
        if 'golden gate' in name.lower() or 'hero shot' in name.lower():
            result["placemark_found"] = True
            result["placemark_name"] = name
            
            # Get description
            desc_elem = pm.find('{http://www.opengis.net/kml/2.2}description')
            if desc_elem is None:
                desc_elem = pm.find('description')
            result["placemark_description"] = desc_elem.text if desc_elem is not None and desc_elem.text else ""
            
            # Look for LookAt element
            lookat = pm.find('.//{http://www.opengis.net/kml/2.2}LookAt')
            if lookat is None:
                lookat = pm.find('.//LookAt')
            
            if lookat is not None:
                result["has_lookat"] = True
                
                # Extract LookAt parameters
                for param in ['latitude', 'longitude', 'range', 'tilt', 'heading', 'altitude']:
                    elem = lookat.find('{http://www.opengis.net/kml/2.2}' + param)
                    if elem is None:
                        elem = lookat.find(param)
                    if elem is not None and elem.text:
                        try:
                            result["lookat"][param] = float(elem.text)
                        except ValueError:
                            pass
            
            break  # Found our placemark
    
    # If not found by name, check for any placemark with LookAt near Golden Gate
    if not result["placemark_found"]:
        for pm in placemarks:
            lookat = pm.find('.//{http://www.opengis.net/kml/2.2}LookAt')
            if lookat is None:
                lookat = pm.find('.//LookAt')
            
            if lookat is not None:
                lat_elem = lookat.find('{http://www.opengis.net/kml/2.2}latitude') or lookat.find('latitude')
                lon_elem = lookat.find('{http://www.opengis.net/kml/2.2}longitude') or lookat.find('longitude')
                
                if lat_elem is not None and lon_elem is not None:
                    try:
                        lat = float(lat_elem.text)
                        lon = float(lon_elem.text)
                        
                        # Check if near Golden Gate Bridge (within 0.1 degrees)
                        if abs(lat - 37.8199) < 0.1 and abs(lon - (-122.4783)) < 0.1:
                            result["placemark_found"] = True
                            
                            name_elem = pm.find('{http://www.opengis.net/kml/2.2}name') or pm.find('name')
                            result["placemark_name"] = name_elem.text if name_elem is not None and name_elem.text else "unnamed"
                            
                            desc_elem = pm.find('{http://www.opengis.net/kml/2.2}description') or pm.find('description')
                            result["placemark_description"] = desc_elem.text if desc_elem is not None and desc_elem.text else ""
                            
                            result["has_lookat"] = True
                            for param in ['latitude', 'longitude', 'range', 'tilt', 'heading', 'altitude']:
                                elem = lookat.find('{http://www.opengis.net/kml/2.2}' + param) or lookat.find(param)
                                if elem is not None and elem.text:
                                    try:
                                        result["lookat"][param] = float(elem.text)
                                    except ValueError:
                                        pass
                            break
                    except ValueError:
                        pass

except Exception as e:
    result["parse_error"] = str(e)

print(json.dumps(result))
PYEOF
)

echo "Parsed KML data: $PARSED_DATA"

# ============================================================
# EXTRACT VALUES FROM PARSED DATA
# ============================================================
PLACEMARK_FOUND=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_found', False))" 2>/dev/null || echo "false")
PLACEMARK_NAME=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_name', ''))" 2>/dev/null || echo "")
PLACEMARK_DESC=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_description', ''))" 2>/dev/null || echo "")
HAS_LOOKAT=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('has_lookat', False))" 2>/dev/null || echo "false")

LOOKAT_LAT=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('lookat', {}).get('latitude') or 'null')" 2>/dev/null || echo "null")
LOOKAT_LON=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('lookat', {}).get('longitude') or 'null')" 2>/dev/null || echo "null")
LOOKAT_RANGE=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('lookat', {}).get('range') or 'null')" 2>/dev/null || echo "null")
LOOKAT_TILT=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('lookat', {}).get('tilt') or 'null')" 2>/dev/null || echo "null")
LOOKAT_HEADING=$(echo "$PARSED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('lookat', {}).get('heading') or 'null')" 2>/dev/null || echo "null")

# ============================================================
# CREATE JSON RESULT FILE
# ============================================================
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "google_earth_running": $GOOGLE_EARTH_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "kml_exists": $KML_EXISTS,
    "kml_modified": $KML_MODIFIED,
    "kml_size_bytes": $KML_SIZE,
    "placemark_found": $PLACEMARK_FOUND,
    "placemark_name": "$PLACEMARK_NAME",
    "placemark_description": "$PLACEMARK_DESC",
    "has_lookat": $HAS_LOOKAT,
    "lookat": {
        "latitude": $LOOKAT_LAT,
        "longitude": $LOOKAT_LON,
        "range": $LOOKAT_RANGE,
        "tilt": $LOOKAT_TILT,
        "heading": $LOOKAT_HEADING
    },
    "parsed_data": $PARSED_DATA
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also copy the raw KML file for backup verification
if [ -f "$KML_FILE" ]; then
    cp "$KML_FILE" /tmp/myplaces_export.kml 2>/dev/null || true
    chmod 666 /tmp/myplaces_export.kml 2>/dev/null || true
fi

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""