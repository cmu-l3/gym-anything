#!/bin/bash
echo "=== Exporting variable_distance_buffer_zones result ==="

source /workspace/scripts/task_utils.sh

# Task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/GIS_Data/exports/variable_buffers.geojson"

# Check file existence and timestamps
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Analyze the GeoJSON content using Python (shapely/json)
# We perform the geometric analysis inside the container where libraries are available
ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys
import math

output_path = "/home/ga/GIS_Data/exports/variable_buffers.geojson"
result = {
    "valid_geojson": False,
    "feature_count": 0,
    "geometry_types": [],
    "areas": [],
    "is_variable": False,
    "area_hierarchy_correct": False,
    "error": None
}

try:
    with open(output_path, 'r') as f:
        data = json.load(f)
    
    result["valid_geojson"] = True
    features = data.get("features", [])
    result["feature_count"] = len(features)
    
    areas = []
    
    # Calculate simple area for polygons
    # Note: Robust area calc requires shapely, but we can try basic check or assume shapely is installed
    # The environment spec installs 'shapely', so we import it.
    from shapely.geometry import shape
    
    for feat in features:
        geom = shape(feat.get("geometry"))
        result["geometry_types"].append(geom.geom_type)
        areas.append(geom.area)
    
    result["areas"] = sorted(areas)
    
    # Check if areas are significantly different (variable buffer check)
    if len(areas) >= 2:
        # Standard deviation or range check
        min_area = min(areas)
        max_area = max(areas)
        # If max area is at least 2x min area, we likely have variable buffers
        # (150m buffer vs 30m buffer is 5x difference in width, area should be ~5x)
        if max_area > 2.0 * min_area:
            result["is_variable"] = True
            
    # Check hierarchy against expected inputs [30, 80, 150]
    # Expected areas for 1km line:
    # 30m buffer ~= 2000 * 30 = 60,000 m2
    # 80m buffer ~= 2000 * 80 = 160,000 m2
    # 150m buffer ~= 2000 * 150 = 300,000 m2
    # We allow generous tolerance, just checking they cluster around these values
    
    expected_areas_approx = [60000, 160000, 300000]
    matched_count = 0
    
    # Sort calculated areas
    sorted_areas = sorted(areas)
    
    # Check if we have 3 areas that roughly match expected magnitudes
    if len(sorted_areas) == 3:
        # Check smallest
        if 40000 < sorted_areas[0] < 80000: matched_count += 1
        # Check middle
        if 130000 < sorted_areas[1] < 190000: matched_count += 1
        # Check largest
        if 250000 < sorted_areas[2] < 350000: matched_count += 1
        
    if matched_count == 3:
        result["area_hierarchy_correct"] = True

except ImportError:
    result["error"] = "Shapely not found"
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# App running check
APP_RUNNING="false"
if pgrep -f "qgis" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="