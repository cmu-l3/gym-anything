#!/bin/bash
echo "=== Exporting generate_random_survey_points result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_SHP="/home/ga/gvsig_data/exports/madagascar_survey.shp"
OUTPUT_SHX="/home/ga/gvsig_data/exports/madagascar_survey.shx"
OUTPUT_DBF="/home/ga/gvsig_data/exports/madagascar_survey.dbf"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if app was running
APP_RUNNING=$(pgrep -f "gvSIG" > /dev/null && echo "true" || echo "false")

# Use embedded Python to parse Shapefile structure (standard lib only)
# We calculate bbox, count, and check field names
PYTHON_SCRIPT=$(cat <<EOF
import struct
import os
import json
import sys

shp_path = "$OUTPUT_SHP"
shx_path = "$OUTPUT_SHX"
dbf_path = "$OUTPUT_DBF"

result = {
    "exists": False,
    "count": 0,
    "bbox": [0, 0, 0, 0],
    "fields": [],
    "valid_timestamps": False
}

try:
    if os.path.exists(shp_path) and os.path.exists(shx_path) and os.path.exists(dbf_path):
        result["exists"] = True
        
        # Check timestamps
        mtime = os.path.getmtime(shp_path)
        task_start = float($TASK_START)
        if mtime > task_start:
            result["valid_timestamps"] = True

        # 1. Get Feature Count from SHX
        # Header is 100 bytes, each record is 8 bytes
        shx_size = os.path.getsize(shx_path)
        if shx_size >= 100:
            result["count"] = (shx_size - 100) // 8

        # 2. Get Bounding Box from SHP Header
        # Bytes 36-68 contain 4 doubles (minx, miny, maxx, maxy)
        with open(shp_path, "rb") as f:
            header = f.read(100)
            if len(header) == 100:
                # Unpack 4 doubles (little endian)
                bbox = struct.unpack("<4d", header[36:68])
                result["bbox"] = list(bbox)

        # 3. Get Field Names from DBF
        # Header structure: 
        # 0-31: Main header
        # 32-n: Field descriptors (32 bytes each)
        # Terminated by 0x0D
        with open(dbf_path, "rb") as f:
            # Read header len (bytes 8-9, little endian short)
            f.seek(8)
            header_len_bytes = f.read(2)
            header_len = struct.unpack("<H", header_len_bytes)[0]
            
            f.seek(32)
            # Loop through field descriptors
            while f.tell() < header_len:
                byte = f.read(1)
                if byte == b'\r': # 0x0D terminator
                    break
                f.seek(-1, 1) # Go back
                
                field_desc = f.read(32)
                if len(field_desc) < 32:
                    break
                    
                # Field name is first 11 bytes, null padded
                name = field_desc[:11].replace(b'\x00', b'').decode('ascii', errors='ignore').strip()
                result["fields"].append(name)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF
)

# Execute Python analysis
echo "Analyzing shapefile structure..."
ANALYSIS_JSON=$(python3 -c "$PYTHON_SCRIPT")
echo "Analysis result: $ANALYSIS_JSON"

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "shapefile_analysis": $ANALYSIS_JSON
}
EOF

# Save to shared location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="