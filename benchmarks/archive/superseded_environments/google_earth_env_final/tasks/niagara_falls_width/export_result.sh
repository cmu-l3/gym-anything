#!/bin/bash
set -euo pipefail

echo "=== Exporting niagara_falls_width task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE any processing
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check output KML file
OUTPUT_PATH="/home/ga/Documents/niagara_falls_measurements.kml"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
KML_VALID="false"
NUM_PLACEMARKS="0"
HAS_FOLDER="false"
HAS_DESCRIPTION="false"
PLACEMARK_NAMES="[]"
PLACEMARK_COORDS="[]"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Validate KML structure and extract data
    KML_ANALYSIS=$(python3 << 'PYEOF'
import json
import xml.etree.ElementTree as ET
import sys

result = {
    "valid": False,
    "num_placemarks": 0,
    "has_folder": False,
    "has_description": False,
    "placemark_names": [],
    "placemark_coords": [],
    "folder_name": "",
    "folder_description": ""
}

try:
    tree = ET.parse("/home/ga/Documents/niagara_falls_measurements.kml")
    root = tree.getroot()
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Try with namespace first, then without
    placemarks = root.findall('.//{http://www.opengis.net/kml/2.2}Placemark')
    if not placemarks:
        placemarks = root.findall('.//Placemark')
    
    result["valid"] = True
    result["num_placemarks"] = len(placemarks)
    
    # Extract placemark data
    for pm in placemarks:
        # Get name
        name_elem = pm.find('.//{http://www.opengis.net/kml/2.2}name')
        if name_elem is None:
            name_elem = pm.find('.//name')
        name = name_elem.text if name_elem is not None and name_elem.text else ""
        result["placemark_names"].append(name)
        
        # Get coordinates
        coord_elem = pm.find('.//{http://www.opengis.net/kml/2.2}coordinates')
        if coord_elem is None:
            coord_elem = pm.find('.//coordinates')
        if coord_elem is not None and coord_elem.text:
            parts = coord_elem.text.strip().split(',')
            if len(parts) >= 2:
                try:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    result["placemark_coords"].append({"lat": lat, "lon": lon})
                except:
                    result["placemark_coords"].append(None)
            else:
                result["placemark_coords"].append(None)
        else:
            result["placemark_coords"].append(None)
    
    # Check for folder
    folders = root.findall('.//{http://www.opengis.net/kml/2.2}Folder')
    if not folders:
        folders = root.findall('.//Folder')
    
    if folders:
        result["has_folder"] = True
        for folder in folders:
            name_elem = folder.find('.//{http://www.opengis.net/kml/2.2}name')
            if name_elem is None:
                name_elem = folder.find('.//name')
            if name_elem is not None and name_elem.text:
                result["folder_name"] = name_elem.text
            
            desc_elem = folder.find('.//{http://www.opengis.net/kml/2.2}description')
            if desc_elem is None:
                desc_elem = folder.find('.//description')
            if desc_elem is not None and desc_elem.text:
                result["folder_description"] = desc_elem.text
                result["has_description"] = True
    
    # Also check document-level description
    if not result["has_description"]:
        doc_descs = root.findall('.//{http://www.opengis.net/kml/2.2}description')
        if not doc_descs:
            doc_descs = root.findall('.//description')
        for desc in doc_descs:
            if desc.text and len(desc.text.strip()) > 10:
                result["has_description"] = True
                result["folder_description"] = desc.text
                break

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)
    
    # Parse the analysis result
    KML_VALID=$(echo "$KML_ANALYSIS" | python3 -c "import json, sys; print(str(json.load(sys.stdin).get('valid', False)).lower())")
    NUM_PLACEMARKS=$(echo "$KML_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('num_placemarks', 0))")
    HAS_FOLDER=$(echo "$KML_ANALYSIS" | python3 -c "import json, sys; print(str(json.load(sys.stdin).get('has_folder', False)).lower())")
    HAS_DESCRIPTION=$(echo "$KML_ANALYSIS" | python3 -c "import json, sys; print(str(json.load(sys.stdin).get('has_description', False)).lower())")
    PLACEMARK_NAMES=$(echo "$KML_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('placemark_names', [])))")
    PLACEMARK_COORDS=$(echo "$KML_ANALYSIS" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin).get('placemark_coords', [])))")
    FOLDER_NAME=$(echo "$KML_ANALYSIS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('folder_name', ''))")
    FOLDER_DESC=$(echo "$KML_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin).get('folder_description', ''); print(d[:200] if d else '')")
fi

# Check if Google Earth was running
GE_RUNNING="false"
GE_WINDOW=""
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW=$(echo "$GE_WINDOWS" | head -1)
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "kml_valid": $KML_VALID,
    "num_placemarks": $NUM_PLACEMARKS,
    "has_folder": $HAS_FOLDER,
    "has_description": $HAS_DESCRIPTION,
    "placemark_names": $PLACEMARK_NAMES,
    "placemark_coords": $PLACEMARK_COORDS,
    "folder_name": "$FOLDER_NAME",
    "folder_description": "$FOLDER_DESC",
    "google_earth_running": $GE_RUNNING,
    "google_earth_window": "$GE_WINDOW",
    "final_screenshot": "/tmp/task_final.png",
    "initial_screenshot": "/tmp/task_initial_state.png"
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