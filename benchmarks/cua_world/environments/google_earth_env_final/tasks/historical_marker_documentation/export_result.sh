#!/bin/bash
set -e
echo "=== Exporting Historical Marker Documentation task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task start time: $TASK_START"
echo "Task end time: $TASK_END"

# Take final screenshot BEFORE any other operations
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_screenshots/final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_screenshots/final_state.png 2>/dev/null || true

if [ -f /tmp/task_screenshots/final_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_screenshots/final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_WINDOW_TITLE=""
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi
echo "Google Earth running: $GE_RUNNING"
echo "Window title: $GE_WINDOW_TITLE"

# Check output file
OUTPUT_PATH="/home/ga/Documents/gettysburg_marker.kml"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
KML_VALID="false"
HAS_PLACEMARK="false"
PLACEMARK_NAME=""
COORDINATES=""
DESCRIPTION_LENGTH="0"
HAS_BOLD="false"
BULLET_COUNT="0"
HAS_LINK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    echo "Output file found: $OUTPUT_PATH"
    echo "File size: $OUTPUT_SIZE bytes"
    echo "File mtime: $OUTPUT_MTIME"
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "File was created during task execution"
    else
        echo "WARNING: File appears to predate task start"
    fi
    
    # Parse KML file using Python
    KML_ANALYSIS=$(python3 << 'PYEOF'
import sys
import re
import json
import xml.etree.ElementTree as ET

result = {
    "valid_kml": False,
    "has_placemark": False,
    "placemark_name": "",
    "coordinates": "",
    "latitude": None,
    "longitude": None,
    "description_length": 0,
    "description_raw": "",
    "has_bold": False,
    "bullet_count": 0,
    "has_link": False,
    "link_url": "",
    "errors": []
}

try:
    with open("/home/ga/Documents/gettysburg_marker.kml", 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Parse XML
    root = ET.fromstring(content)
    result["valid_kml"] = True
    
    # Define namespaces
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Find Placemark
    placemark = root.find('.//kml:Placemark', ns)
    if placemark is None:
        placemark = root.find('.//Placemark')
    
    if placemark is not None:
        result["has_placemark"] = True
        
        # Get name
        name_elem = placemark.find('kml:name', ns)
        if name_elem is None:
            name_elem = placemark.find('name')
        if name_elem is not None and name_elem.text:
            result["placemark_name"] = name_elem.text.strip()
        
        # Get coordinates
        coord_elem = placemark.find('.//kml:coordinates', ns)
        if coord_elem is None:
            coord_elem = placemark.find('.//coordinates')
        if coord_elem is not None and coord_elem.text:
            coords = coord_elem.text.strip()
            result["coordinates"] = coords
            parts = coords.split(',')
            if len(parts) >= 2:
                try:
                    result["longitude"] = float(parts[0].strip())
                    result["latitude"] = float(parts[1].strip())
                except:
                    pass
        
        # Get description
        desc_elem = placemark.find('kml:description', ns)
        if desc_elem is None:
            desc_elem = placemark.find('description')
        if desc_elem is not None and desc_elem.text:
            desc = desc_elem.text
            result["description_raw"] = desc
            result["description_length"] = len(desc)
            
            # Check for bold tags
            if re.search(r'<b[^>]*>|<strong[^>]*>', desc, re.IGNORECASE):
                result["has_bold"] = True
            
            # Count bullet points (HTML list items or bullet characters)
            li_count = len(re.findall(r'<li[^>]*>', desc, re.IGNORECASE))
            if li_count > 0:
                result["bullet_count"] = li_count
            else:
                # Count bullet characters
                bullet_chars = ['•', '◦', '▪', '▸', '●', '○']
                bullet_count = sum(desc.count(char) for char in bullet_chars)
                # Also count lines starting with - or *
                bullet_count += len(re.findall(r'^\s*[-*]\s+', desc, re.MULTILINE))
                result["bullet_count"] = bullet_count
            
            # Check for hyperlink
            link_match = re.search(r'<a[^>]+href=["\']([^"\']+)["\']', desc, re.IGNORECASE)
            if link_match:
                result["has_link"] = True
                result["link_url"] = link_match.group(1)
            elif 'nps.gov/gett' in desc.lower():
                result["has_link"] = True
                result["link_url"] = "plain text URL"

except ET.ParseError as e:
    result["errors"].append(f"XML parse error: {str(e)}")
except Exception as e:
    result["errors"].append(f"Error: {str(e)}")

print(json.dumps(result))
PYEOF
)
    
    echo "KML Analysis: $KML_ANALYSIS"
    
    # Extract values from Python output
    KML_VALID=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('valid_kml') else 'false')" 2>/dev/null || echo "false")
    HAS_PLACEMARK=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('has_placemark') else 'false')" 2>/dev/null || echo "false")
    PLACEMARK_NAME=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('placemark_name', ''))" 2>/dev/null || echo "")
    COORDINATES=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('coordinates', ''))" 2>/dev/null || echo "")
    LATITUDE=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('latitude') or '')" 2>/dev/null || echo "")
    LONGITUDE=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('longitude') or '')" 2>/dev/null || echo "")
    DESCRIPTION_LENGTH=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description_length', 0))" 2>/dev/null || echo "0")
    HAS_BOLD=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('has_bold') else 'false')" 2>/dev/null || echo "false")
    BULLET_COUNT=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('bullet_count', 0))" 2>/dev/null || echo "0")
    HAS_LINK=$(echo "$KML_ANALYSIS" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('has_link') else 'false')" 2>/dev/null || echo "false")
    
else
    echo "Output file NOT found at $OUTPUT_PATH"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "kml_valid": $KML_VALID,
    "has_placemark": $HAS_PLACEMARK,
    "placemark_name": "$PLACEMARK_NAME",
    "coordinates": "$COORDINATES",
    "latitude": ${LATITUDE:-null},
    "longitude": ${LONGITUDE:-null},
    "description_length": $DESCRIPTION_LENGTH,
    "has_bold_header": $HAS_BOLD,
    "bullet_count": $BULLET_COUNT,
    "has_hyperlink": $HAS_LINK,
    "initial_screenshot": "/tmp/task_screenshots/initial_state.png",
    "final_screenshot": "/tmp/task_screenshots/final_state.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Result Summary ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="