#!/bin/bash
set -euo pipefail

echo "=== Exporting custom_placemark_style task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# ============================================================
# Take final screenshot FIRST (before any file operations)
# ============================================================
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
fi

# ============================================================
# Find and analyze myplaces.kml
# ============================================================
MYPLACES_PATHS=(
    "/home/ga/.googleearth/myplaces.kml"
    "/home/ga/.config/Google/googleearth/myplaces.kml"
    "/home/ga/.local/share/Google/googleearth/myplaces.kml"
)

MYPLACES_PATH=""
for path in "${MYPLACES_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MYPLACES_PATH="$path"
        echo "Found myplaces.kml at: $path"
        break
    fi
done

# Initialize result variables
MYPLACES_EXISTS="false"
MYPLACES_MODIFIED="false"
FINAL_MTIME="0"
FINAL_PLACEMARK_COUNT="0"
PLACEMARK_FOUND="false"
PLACEMARK_NAME=""
PLACEMARK_COORDINATES=""
ICON_COLOR=""
DESCRIPTION_TEXT=""
LOOKAT_RANGE=""

if [ -n "$MYPLACES_PATH" ] && [ -f "$MYPLACES_PATH" ]; then
    MYPLACES_EXISTS="true"
    FINAL_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    FINAL_PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_PATH" 2>/dev/null || echo "0")
    
    # Check if file was modified during task
    INITIAL_MTIME=$(cat /tmp/initial_state.json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('initial_mtime', 0))" 2>/dev/null || echo "0")
    if [ "$FINAL_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_MODIFIED="true"
        echo "myplaces.kml was modified during task"
    fi
    
    # Copy the KML file for verification
    cp "$MYPLACES_PATH" /tmp/myplaces_final.kml 2>/dev/null || true
    chmod 644 /tmp/myplaces_final.kml 2>/dev/null || true
    
    # Parse KML to find the placemark using Python
    python3 << 'PYEOF' > /tmp/placemark_analysis.json 2>/dev/null || echo '{}' > /tmp/placemark_analysis.json
import xml.etree.ElementTree as ET
import json
import re

def find_myplaces():
    paths = [
        "/tmp/myplaces_final.kml",
        "/home/ga/.googleearth/myplaces.kml",
        "/home/ga/.config/Google/googleearth/myplaces.kml"
    ]
    for p in paths:
        try:
            return ET.parse(p)
        except:
            continue
    return None

result = {
    "placemark_found": False,
    "placemark_name": "",
    "coordinates": "",
    "latitude": 0,
    "longitude": 0,
    "icon_color": "",
    "description": "",
    "lookat_range": 0,
    "icon_href": "",
    "all_placemarks": []
}

tree = find_myplaces()
if tree:
    root = tree.getroot()
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Try with namespace first, then without
    placemarks = root.findall('.//{http://www.opengis.net/kml/2.2}Placemark')
    if not placemarks:
        placemarks = root.findall('.//Placemark')
    
    for pm in placemarks:
        # Get name
        name_elem = pm.find('{http://www.opengis.net/kml/2.2}name')
        if name_elem is None:
            name_elem = pm.find('name')
        
        pm_name = name_elem.text if name_elem is not None and name_elem.text else ""
        result["all_placemarks"].append(pm_name)
        
        # Check if this is our target placemark
        if "NYC Regional Office" in pm_name:
            result["placemark_found"] = True
            result["placemark_name"] = pm_name
            
            # Get coordinates
            coords_elem = pm.find('.//{http://www.opengis.net/kml/2.2}coordinates')
            if coords_elem is None:
                coords_elem = pm.find('.//coordinates')
            if coords_elem is not None and coords_elem.text:
                coords = coords_elem.text.strip().split(',')
                if len(coords) >= 2:
                    result["coordinates"] = coords_elem.text.strip()
                    result["longitude"] = float(coords[0])
                    result["latitude"] = float(coords[1])
            
            # Get icon color
            icon_style = pm.find('.//{http://www.opengis.net/kml/2.2}IconStyle')
            if icon_style is None:
                icon_style = pm.find('.//IconStyle')
            if icon_style is not None:
                color_elem = icon_style.find('{http://www.opengis.net/kml/2.2}color')
                if color_elem is None:
                    color_elem = icon_style.find('color')
                if color_elem is not None and color_elem.text:
                    result["icon_color"] = color_elem.text
            
            # Get icon href
            icon = pm.find('.//{http://www.opengis.net/kml/2.2}Icon')
            if icon is None:
                icon = pm.find('.//Icon')
            if icon is not None:
                href = icon.find('{http://www.opengis.net/kml/2.2}href')
                if href is None:
                    href = icon.find('href')
                if href is not None and href.text:
                    result["icon_href"] = href.text
            
            # Get description
            desc_elem = pm.find('{http://www.opengis.net/kml/2.2}description')
            if desc_elem is None:
                desc_elem = pm.find('description')
            if desc_elem is not None and desc_elem.text:
                result["description"] = desc_elem.text
            
            # Get LookAt range
            lookat = pm.find('.//{http://www.opengis.net/kml/2.2}LookAt')
            if lookat is None:
                lookat = pm.find('.//LookAt')
            if lookat is not None:
                range_elem = lookat.find('{http://www.opengis.net/kml/2.2}range')
                if range_elem is None:
                    range_elem = lookat.find('range')
                if range_elem is not None and range_elem.text:
                    try:
                        result["lookat_range"] = float(range_elem.text)
                    except:
                        pass
            
            break

print(json.dumps(result))
PYEOF

    # Read analysis results
    if [ -f /tmp/placemark_analysis.json ]; then
        PLACEMARK_FOUND=$(python3 -c "import json; print('true' if json.load(open('/tmp/placemark_analysis.json')).get('placemark_found') else 'false')" 2>/dev/null || echo "false")
        PLACEMARK_NAME=$(python3 -c "import json; print(json.load(open('/tmp/placemark_analysis.json')).get('placemark_name', ''))" 2>/dev/null || echo "")
        PLACEMARK_COORDINATES=$(python3 -c "import json; print(json.load(open('/tmp/placemark_analysis.json')).get('coordinates', ''))" 2>/dev/null || echo "")
        ICON_COLOR=$(python3 -c "import json; print(json.load(open('/tmp/placemark_analysis.json')).get('icon_color', ''))" 2>/dev/null || echo "")
        DESCRIPTION_TEXT=$(python3 -c "import json; print(json.load(open('/tmp/placemark_analysis.json')).get('description', ''))" 2>/dev/null || echo "")
        LOOKAT_RANGE=$(python3 -c "import json; print(json.load(open('/tmp/placemark_analysis.json')).get('lookat_range', 0))" 2>/dev/null || echo "0")
    fi
fi

# ============================================================
# Check if Google Earth is still running
# ============================================================
GE_RUNNING="false"
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window info
GE_WINDOW_TITLE=""
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
    GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi

# ============================================================
# Create comprehensive result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_path": "$MYPLACES_PATH",
    "myplaces_modified_during_task": $MYPLACES_MODIFIED,
    "myplaces_mtime": $FINAL_MTIME,
    "placemark_count": $FINAL_PLACEMARK_COUNT,
    "placemark_found": $PLACEMARK_FOUND,
    "placemark_name": "$PLACEMARK_NAME",
    "placemark_coordinates": "$PLACEMARK_COORDINATES",
    "icon_color": "$ICON_COLOR",
    "description": "$DESCRIPTION_TEXT",
    "lookat_range": $LOOKAT_RANGE,
    "google_earth_running": $GE_RUNNING,
    "window_title": "$GE_WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size": $SCREENSHOT_SIZE
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="