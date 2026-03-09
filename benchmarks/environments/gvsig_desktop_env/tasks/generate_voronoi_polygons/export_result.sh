#!/bin/bash
echo "=== Exporting generate_voronoi_polygons result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_SHP="/home/ga/gvsig_data/exports/voronoi_cities.shp"
OUTPUT_DBF="/home/ga/gvsig_data/exports/voronoi_cities.dbf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Analyze Output File (Python script to parse binary headers)
# We do this inside the container to avoid dependency issues on the verifier side
# and to package the metadata into a clean JSON.

cat > /tmp/analyze_shapefile.py << 'PYEOF'
import struct
import sys
import os
import json
import time

shp_path = sys.argv[1]
dbf_path = sys.argv[2]
task_start = float(sys.argv[3])

result = {
    "exists": False,
    "created_during_task": False,
    "file_size": 0,
    "geometry_type": -1,
    "feature_count": 0,
    "error": ""
}

try:
    if os.path.exists(shp_path):
        result["exists"] = True
        stats = os.stat(shp_path)
        result["file_size"] = stats.st_size
        
        # Check modification time
        if stats.st_mtime > task_start:
            result["created_during_task"] = True
            
        # Parse SHP Header (first 100 bytes)
        with open(shp_path, "rb") as f:
            header = f.read(100)
            if len(header) >= 36:
                # Byte 32-35: Shape Type (Little Endian Integer)
                # 1=Point, 3=PolyLine, 5=Polygon, 8=MultiPoint
                shape_type = struct.unpack("<i", header[32:36])[0]
                result["geometry_type"] = shape_type

    if os.path.exists(dbf_path):
        # Parse DBF Header to get record count
        with open(dbf_path, "rb") as f:
            header = f.read(32)
            if len(header) >= 8:
                # Byte 4-7: Number of records (Little Endian Integer)
                num_records = struct.unpack("<I", header[4:8])[0]
                result["feature_count"] = num_records

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run analysis
if [ -f "$OUTPUT_SHP" ]; then
    ANALYSIS_JSON=$(python3 /tmp/analyze_shapefile.py "$OUTPUT_SHP" "$OUTPUT_DBF" "$TASK_START")
else
    ANALYSIS_JSON='{"exists": false, "created_during_task": false, "file_size": 0, "geometry_type": -1, "feature_count": 0}'
fi

# 3. Check App State
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Construct Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $ANALYSIS_JSON
}
EOF

# Move to final location (handle permissions)
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="