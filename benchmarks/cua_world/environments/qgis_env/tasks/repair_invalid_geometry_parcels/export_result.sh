#!/bin/bash
echo "=== Exporting repair_invalid_geometry_parcels result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

take_screenshot /tmp/task_end.png

OUTPUT_FILE="/home/ga/GIS_Data/exports/parcels_fixed.geojson"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Analyze the output using Python and Shapely
# We check:
# 1. File exists
# 2. Created after start time
# 3. Valid JSON
# 4. All geometries are valid (using shapely.is_valid)
# 5. Attributes preserved

ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys
import os
import time
from shapely.geometry import shape

output_path = "/home/ga/GIS_Data/exports/parcels_fixed.geojson"
task_start = int(os.environ.get('TASK_START', 0))

result = {
    "file_exists": False,
    "file_created_during_task": False,
    "is_valid_json": False,
    "feature_count": 0,
    "all_geometries_valid": False,
    "invalid_count": 0,
    "attributes_preserved": False,
    "doe_owner_found": False,
    "error": None
}

if os.path.exists(output_path):
    result["file_exists"] = True
    mtime = int(os.path.getmtime(output_path))
    if mtime > task_start:
        result["file_created_during_task"] = True
    
    try:
        with open(output_path, 'r') as f:
            data = json.load(f)
        
        result["is_valid_json"] = True
        
        if data.get("type") == "FeatureCollection":
            features = data.get("features", [])
            result["feature_count"] = len(features)
            
            valid_count = 0
            invalid_count = 0
            doe_found = False
            has_attributes = False
            
            for feat in features:
                # Check geometry validity
                geom = feat.get("geometry")
                if geom:
                    try:
                        s_geom = shape(geom)
                        if s_geom.is_valid:
                            valid_count += 1
                        else:
                            invalid_count += 1
                    except Exception:
                        invalid_count += 1
                
                # Check attributes
                props = feat.get("properties", {})
                if props.get("owner") == "Doe":
                    doe_found = True
                if "owner" in props and "type" in props:
                    has_attributes = True

            result["all_geometries_valid"] = (invalid_count == 0 and result["feature_count"] > 0)
            result["invalid_count"] = invalid_count
            result["attributes_preserved"] = has_attributes
            result["doe_owner_found"] = doe_found

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Save result to file
cat > /tmp/task_result.json << EOF
{
    "timestamp": "$(date -Iseconds)",
    "analysis": $ANALYSIS_JSON
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="