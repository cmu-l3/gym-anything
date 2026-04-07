#!/bin/bash
echo "=== Exporting export_quakeml_fdsn result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/exports/noto_quakeml.xml"

# Take final screenshot
take_screenshot /tmp/task_final.png

# ─── 1. File Metadata ────────────────────────────────────────────────────────
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# ─── 2. Parse XML and Extract Content via Python ─────────────────────────────
# We use Python locally in the container to robustly parse the XML and handle namespaces
TEMP_EXTRACT_PY=$(mktemp /tmp/extract_xml.XXXXXX.py)
cat > "$TEMP_EXTRACT_PY" << 'PYEOF'
import sys, json, os
import xml.etree.ElementTree as ET

output_path = "/home/ga/exports/noto_quakeml.xml"
result = {
    "is_valid_xml": False,
    "has_quakeml_ns": False,
    "has_bed_ns": False,
    "has_event_structure": False,
    "extracted_lat": None,
    "extracted_lon": None,
    "extracted_mag": None,
    "error": None
}

if not os.path.exists(output_path):
    print(json.dumps(result))
    sys.exit(0)

try:
    with open(output_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    # Check namespaces in text (robust against prefix changes)
    if "quakeml.org/xmlns/quakeml/1.2" in content:
        result["has_quakeml_ns"] = True
    if "quakeml.org/xmlns/bed/1.2" in content:
        result["has_bed_ns"] = True

    # Parse XML
    root = ET.fromstring(content)
    result["is_valid_xml"] = True
    
    # Strip namespaces for easier path searching
    for elem in root.iter():
        if '}' in elem.tag:
            elem.tag = elem.tag.split('}', 1)[1]
            
    # Check basic hierarchy
    event = root.find('.//event')
    if event is not None:
        result["has_event_structure"] = True
        
    # Extract Coordinates
    lat_elem = root.find('.//latitude/value')
    if lat_elem is not None and lat_elem.text:
        try: result["extracted_lat"] = float(lat_elem.text)
        except: pass

    lon_elem = root.find('.//longitude/value')
    if lon_elem is not None and lon_elem.text:
        try: result["extracted_lon"] = float(lon_elem.text)
        except: pass
        
    # Extract Magnitude
    mag_elem = root.find('.//mag/value')
    if mag_elem is not None and mag_elem.text:
        try: result["extracted_mag"] = float(mag_elem.text)
        except: pass

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

XML_ANALYSIS=$(python3 "$TEMP_EXTRACT_PY")
rm -f "$TEMP_EXTRACT_PY"

# ─── 3. Combine with Ground Truth ────────────────────────────────────────────
GT_JSON="{}"
if [ -f /tmp/ground_truth.json ]; then
    GT_JSON=$(cat /tmp/ground_truth.json)
fi

# ─── 4. Export Final JSON ────────────────────────────────────────────────────
TEMP_RESULT=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_RESULT" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "xml_analysis": $XML_ANALYSIS,
    "ground_truth": $GT_JSON
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_RESULT" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_RESULT"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="