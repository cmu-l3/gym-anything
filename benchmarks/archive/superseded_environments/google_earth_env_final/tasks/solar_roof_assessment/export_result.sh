#!/bin/bash
set -e
echo "=== Exporting Solar Roof Assessment task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
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
fi

# Check Google Earth window state
GE_RUNNING="false"
GE_WINDOW_TITLE=""
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi

# Check myplaces.kml file
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
MYPLACES_EXISTS="false"
MYPLACES_MTIME="0"
MYPLACES_SIZE="0"
MYPLACES_MODIFIED="false"
MYPLACES_CONTENT=""
PLACEMARK_COUNT="0"

if [ -f "$MYPLACES_FILE" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES_FILE" 2>/dev/null || echo "0")
    PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_MODIFIED="true"
    fi
    
    # Copy the KML content for verification
    cp "$MYPLACES_FILE" /tmp/myplaces_final.kml 2>/dev/null || true
    
    # Extract content (limit size for JSON safety)
    MYPLACES_CONTENT=$(head -c 50000 "$MYPLACES_FILE" 2>/dev/null | base64 -w 0 || echo "")
fi

# Compare with initial state
INITIAL_PLACEMARK_COUNT=$(cat /tmp/initial_state.json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_count', 0))" 2>/dev/null || echo "0")
NEW_PLACEMARKS=$((PLACEMARK_COUNT - INITIAL_PLACEMARK_COUNT))

# Search for solar assessment placemark
SOLAR_PLACEMARK_FOUND="false"
SOLAR_PLACEMARK_NAME=""
SOLAR_PLACEMARK_DESCRIPTION=""
SOLAR_PLACEMARK_COORDS=""

if [ -f "$MYPLACES_FILE" ]; then
    # Use Python to parse KML and find matching placemark
    python3 << 'PYEOF' > /tmp/placemark_search.json 2>/dev/null || echo '{"found": false}' > /tmp/placemark_search.json
import xml.etree.ElementTree as ET
import json
import re

def find_solar_placemark(kml_path):
    result = {
        "found": False,
        "name": "",
        "description": "",
        "latitude": None,
        "longitude": None,
        "has_ikea": False,
        "has_solar": False,
        "has_area": False,
        "has_orientation": False,
        "area_value": None,
        "area_unit": None
    }
    
    try:
        tree = ET.parse(kml_path)
        root = tree.getroot()
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Find all placemarks
        for pm in root.iter('{http://www.opengis.net/kml/2.2}Placemark'):
            name_elem = pm.find('{http://www.opengis.net/kml/2.2}name')
            desc_elem = pm.find('{http://www.opengis.net/kml/2.2}description')
            coord_elem = pm.find('.//{http://www.opengis.net/kml/2.2}coordinates')
            
            name = name_elem.text if name_elem is not None and name_elem.text else ""
            desc = desc_elem.text if desc_elem is not None and desc_elem.text else ""
            
            name_lower = name.lower()
            has_ikea = 'ikea' in name_lower
            has_solar = 'solar' in name_lower
            
            if has_ikea and has_solar:
                result["found"] = True
                result["name"] = name
                result["description"] = desc
                result["has_ikea"] = True
                result["has_solar"] = True
                
                # Parse coordinates
                if coord_elem is not None and coord_elem.text:
                    coords = coord_elem.text.strip().split(',')
                    if len(coords) >= 2:
                        try:
                            result["longitude"] = float(coords[0])
                            result["latitude"] = float(coords[1])
                        except ValueError:
                            pass
                
                # Check description for area
                desc_lower = desc.lower() if desc else ""
                area_patterns = [
                    r'([\d,]+(?:\.\d+)?)\s*(sq\.?\s*ft|square\s*feet|sqft)',
                    r'([\d,]+(?:\.\d+)?)\s*(sq\.?\s*m|square\s*meters?|sqm)',
                    r'([\d,]+(?:\.\d+)?)\s*(acres?)',
                ]
                for pattern in area_patterns:
                    match = re.search(pattern, desc_lower)
                    if match:
                        result["has_area"] = True
                        try:
                            result["area_value"] = float(match.group(1).replace(',', ''))
                            result["area_unit"] = match.group(2)
                        except:
                            pass
                        break
                
                # Check for orientation
                orientation_patterns = [
                    r'\b(north|south|east|west|n|s|e|w)\b',
                    r'\b(nw|ne|sw|se|n-s|e-w)\b',
                    r'\b(northwest|northeast|southwest|southeast)\b',
                    r'orientation',
                    r'aligned',
                    r'facing'
                ]
                for pattern in orientation_patterns:
                    if re.search(pattern, desc_lower):
                        result["has_orientation"] = True
                        break
                
                break
        
        # Also try without namespace
        if not result["found"]:
            for pm in root.iter('Placemark'):
                name_elem = pm.find('name')
                desc_elem = pm.find('description')
                coord_elem = pm.find('.//coordinates')
                
                name = name_elem.text if name_elem is not None and name_elem.text else ""
                desc = desc_elem.text if desc_elem is not None and desc_elem.text else ""
                
                name_lower = name.lower()
                has_ikea = 'ikea' in name_lower
                has_solar = 'solar' in name_lower
                
                if has_ikea and has_solar:
                    result["found"] = True
                    result["name"] = name
                    result["description"] = desc
                    result["has_ikea"] = True
                    result["has_solar"] = True
                    
                    if coord_elem is not None and coord_elem.text:
                        coords = coord_elem.text.strip().split(',')
                        if len(coords) >= 2:
                            try:
                                result["longitude"] = float(coords[0])
                                result["latitude"] = float(coords[1])
                            except ValueError:
                                pass
                    
                    desc_lower = desc.lower() if desc else ""
                    area_patterns = [
                        r'([\d,]+(?:\.\d+)?)\s*(sq\.?\s*ft|square\s*feet|sqft)',
                        r'([\d,]+(?:\.\d+)?)\s*(sq\.?\s*m|square\s*meters?|sqm)',
                        r'([\d,]+(?:\.\d+)?)\s*(acres?)',
                    ]
                    for pattern in area_patterns:
                        match = re.search(pattern, desc_lower)
                        if match:
                            result["has_area"] = True
                            try:
                                result["area_value"] = float(match.group(1).replace(',', ''))
                                result["area_unit"] = match.group(2)
                            except:
                                pass
                            break
                    
                    orientation_patterns = [
                        r'\b(north|south|east|west|n|s|e|w)\b',
                        r'\b(nw|ne|sw|se|n-s|e-w)\b',
                        r'\b(northwest|northeast|southwest|southeast)\b',
                        r'orientation', r'aligned', r'facing'
                    ]
                    for pattern in orientation_patterns:
                        if re.search(pattern, desc_lower):
                            result["has_orientation"] = True
                            break
                    break
                    
    except Exception as e:
        result["error"] = str(e)
    
    return result

result = find_solar_placemark("/home/ga/.googleearth/myplaces.kml")
print(json.dumps(result))
PYEOF

    # Read placemark search results
    if [ -f /tmp/placemark_search.json ]; then
        SOLAR_PLACEMARK_FOUND=$(python3 -c "import json; print(str(json.load(open('/tmp/placemark_search.json')).get('found', False)).lower())" 2>/dev/null || echo "false")
        SOLAR_PLACEMARK_NAME=$(python3 -c "import json; print(json.load(open('/tmp/placemark_search.json')).get('name', ''))" 2>/dev/null || echo "")
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_mtime": $MYPLACES_MTIME,
    "myplaces_size": $MYPLACES_SIZE,
    "myplaces_modified_during_task": $MYPLACES_MODIFIED,
    "total_placemark_count": $PLACEMARK_COUNT,
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "new_placemarks_created": $NEW_PLACEMARKS,
    "solar_placemark_found": $SOLAR_PLACEMARK_FOUND,
    "solar_placemark_name": "$SOLAR_PLACEMARK_NAME",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final_state.png",
    "myplaces_copy_path": "/tmp/myplaces_final.kml",
    "placemark_details_path": "/tmp/placemark_search.json"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task Result Summary ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="