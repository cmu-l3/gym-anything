#!/bin/bash
echo "=== Exporting Geofence Parameter Export task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task end time: $TASK_END"
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other operations
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

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_PATH="/home/ga/Documents/angkor_geofence.kml"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Copy KML file to /tmp for easier access
    cp "$OUTPUT_PATH" /tmp/angkor_geofence.kml 2>/dev/null || true
    
    # Basic validation - check if it's valid XML
    if python3 -c "import xml.etree.ElementTree as ET; ET.parse('$OUTPUT_PATH')" 2>/dev/null; then
        KML_VALID_XML="true"
    else
        KML_VALID_XML="false"
    fi
    
    echo "Output file found:"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME"
    echo "  Created during task: $FILE_CREATED_DURING_TASK"
    echo "  Valid XML: $KML_VALID_XML"
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    KML_VALID_XML="false"
    echo "Output file NOT found at: $OUTPUT_PATH"
fi

# ================================================================
# CHECK FOR ANY KML FILES CREATED
# ================================================================
KML_FILES_FOUND=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
OTHER_KML_FILES=""
if [ "$KML_FILES_FOUND" -gt "0" ]; then
    OTHER_KML_FILES=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# ================================================================
# PARSE KML CONTENT (if file exists)
# ================================================================
POLYGON_COUNT="0"
PLACEMARK_COUNT="0"
HAS_POLYGON_ELEMENT="false"
HAS_CENTER_PLACEMARK="false"
POLYGON_NAME=""
CENTER_PLACEMARK_NAME=""
CENTER_COORDS=""

if [ "$OUTPUT_EXISTS" = "true" ] && [ "$KML_VALID_XML" = "true" ]; then
    # Parse KML with Python
    KML_ANALYSIS=$(python3 << 'PYEOF'
import json
import xml.etree.ElementTree as ET
import re

result = {
    "polygon_count": 0,
    "placemark_count": 0,
    "has_polygon_element": False,
    "has_center_placemark": False,
    "polygon_name": "",
    "center_placemark_name": "",
    "center_coords": "",
    "polygon_coords": [],
    "all_names": []
}

try:
    tree = ET.parse("/home/ga/Documents/angkor_geofence.kml")
    root = tree.getroot()
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Find all elements (with and without namespace)
    def find_all(root, tag):
        elements = []
        # With namespace
        elements.extend(root.findall(f".//{{{ns['kml']}}}{tag}"))
        # Without namespace
        elements.extend(root.findall(f".//{tag}"))
        # Manual search for namespaced elements
        for elem in root.iter():
            local_name = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
            if local_name == tag and elem not in elements:
                elements.append(elem)
        return elements
    
    def get_text(elem, tag):
        for child in elem:
            local_name = child.tag.split('}')[-1] if '}' in child.tag else child.tag
            if local_name == tag:
                return child.text or ""
        return ""
    
    # Count and analyze Placemarks
    placemarks = find_all(root, "Placemark")
    result["placemark_count"] = len(placemarks)
    
    for pm in placemarks:
        name = get_text(pm, "name")
        if name:
            result["all_names"].append(name)
        
        # Check for polygon
        has_polygon = False
        for child in pm.iter():
            local_name = child.tag.split('}')[-1] if '}' in child.tag else child.tag
            if local_name == "Polygon":
                has_polygon = True
                result["polygon_count"] += 1
                result["has_polygon_element"] = True
                if name:
                    result["polygon_name"] = name
                
                # Get polygon coordinates
                for coord_elem in child.iter():
                    coord_name = coord_elem.tag.split('}')[-1] if '}' in coord_elem.tag else coord_elem.tag
                    if coord_name == "coordinates" and coord_elem.text:
                        coords_text = coord_elem.text.strip()
                        for part in coords_text.split():
                            vals = part.split(',')
                            if len(vals) >= 2:
                                try:
                                    lon = float(vals[0])
                                    lat = float(vals[1])
                                    result["polygon_coords"].append([lon, lat])
                                except:
                                    pass
                break
        
        # Check for center placemark (Point, not Polygon)
        if not has_polygon:
            for child in pm.iter():
                local_name = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if local_name == "Point":
                    if name and ("center" in name.lower() or "geofence" in name.lower()):
                        result["has_center_placemark"] = True
                        result["center_placemark_name"] = name
                        
                        # Get coordinates
                        for coord_elem in child.iter():
                            coord_name = coord_elem.tag.split('}')[-1] if '}' in coord_elem.tag else coord_elem.tag
                            if coord_name == "coordinates" and coord_elem.text:
                                result["center_coords"] = coord_elem.text.strip()
                    break
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)
    
    if [ -n "$KML_ANALYSIS" ]; then
        POLYGON_COUNT=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('polygon_count', 0))" 2>/dev/null || echo "0")
        PLACEMARK_COUNT=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_count', 0))" 2>/dev/null || echo "0")
        HAS_POLYGON_ELEMENT=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('has_polygon_element') else 'false')" 2>/dev/null || echo "false")
        HAS_CENTER_PLACEMARK=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('has_center_placemark') else 'false')" 2>/dev/null || echo "false")
        POLYGON_NAME=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('polygon_name', ''))" 2>/dev/null || echo "")
        CENTER_PLACEMARK_NAME=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('center_placemark_name', ''))" 2>/dev/null || echo "")
        CENTER_COORDS=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('center_coords', ''))" 2>/dev/null || echo "")
        
        echo "KML Analysis:"
        echo "  Polygon count: $POLYGON_COUNT"
        echo "  Placemark count: $PLACEMARK_COUNT"
        echo "  Has polygon: $HAS_POLYGON_ELEMENT"
        echo "  Has center placemark: $HAS_CENTER_PLACEMARK"
        echo "  Polygon name: $POLYGON_NAME"
        echo "  Center placemark name: $CENTER_PLACEMARK_NAME"
        
        # Save full analysis
        echo "$KML_ANALYSIS" > /tmp/kml_analysis.json
    fi
fi

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
    "kml_valid_xml": $KML_VALID_XML,
    "polygon_count": $POLYGON_COUNT,
    "placemark_count": $PLACEMARK_COUNT,
    "has_polygon_element": $HAS_POLYGON_ELEMENT,
    "has_center_placemark": $HAS_CENTER_PLACEMARK,
    "polygon_name": "$POLYGON_NAME",
    "center_placemark_name": "$CENTER_PLACEMARK_NAME",
    "center_coords": "$CENTER_COORDS",
    "kml_files_found": $KML_FILES_FOUND,
    "other_kml_files": "$OTHER_KML_FILES",
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json