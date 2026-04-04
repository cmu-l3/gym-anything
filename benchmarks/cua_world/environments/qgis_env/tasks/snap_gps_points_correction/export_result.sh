#!/bin/bash
echo "=== Exporting snap_gps_points_correction result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

EXPORT_FILE="/home/ga/GIS_Data/exports/snapped_points.geojson"
INPUT_LINES="/home/ga/GIS_Data/sample_lines.geojson"
INPUT_POINTS="/home/ga/GIS_Data/noisy_gps_points.geojson"

# Record file stats
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED="false"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$EXPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPORT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED="true"
    fi
fi

# Analyze geometry using Python (shapely)
# We perform the check INSIDE the container where libraries are guaranteed
ANALYSIS_JSON="{}"

if [ "$FILE_EXISTS" = "true" ]; then
    ANALYSIS_JSON=$(python3 << PYEOF
import json
import sys
import math

try:
    from shapely.geometry import shape, Point, LineString, MultiLineString
    from shapely.ops import nearest_points
except ImportError:
    # Fallback if shapely is missing (unlikely in this env)
    print(json.dumps({"error": "shapely_missing"}))
    sys.exit(0)

try:
    # Load Lines
    with open("$INPUT_LINES") as f:
        lines_data = json.load(f)
    lines_geoms = [shape(feat["geometry"]) for feat in lines_data["features"]]
    
    # Create a single MultiLineString for distance checking
    # Flatten if necessary
    all_lines = []
    for g in lines_geoms:
        if g.geom_type == 'LineString':
            all_lines.append(g)
        elif g.geom_type == 'MultiLineString':
            all_lines.extend(g.geoms)
    
    network = MultiLineString(all_lines)

    # Load Original Points (to check movement)
    with open("$INPUT_POINTS") as f:
        orig_data = json.load(f)
    orig_coords = []
    for feat in orig_data["features"]:
        p = shape(feat["geometry"])
        orig_coords.append((p.x, p.y))

    # Load Result Points
    with open("$EXPORT_FILE") as f:
        res_data = json.load(f)
    
    if res_data.get("type") != "FeatureCollection":
        raise ValueError("Output is not a FeatureCollection")

    res_features = res_data.get("features", [])
    feature_count = len(res_features)
    
    max_dist_to_line = 0.0
    total_movement = 0.0
    valid_geoms = True
    
    res_coords = []

    for i, feat in enumerate(res_features):
        geom = shape(feat["geometry"])
        if geom.geom_type != 'Point':
            valid_geoms = False
            continue
        
        # Distance to network
        dist = network.distance(geom)
        if dist > max_dist_to_line:
            max_dist_to_line = dist
            
        res_coords.append((geom.x, geom.y))

    # Calculate movement (assuming order preserved or small dataset)
    # Since QGIS snap usually preserves order/ID, we compare by index if counts match
    movement_detected = False
    if len(orig_coords) == len(res_coords):
        moved_count = 0
        for i in range(len(orig_coords)):
            ox, oy = orig_coords[i]
            rx, ry = res_coords[i]
            d = math.sqrt((ox-rx)**2 + (oy-ry)**2)
            if d > 1e-6: # Moved more than micro-fraction
                moved_count += 1
        
        if moved_count > 0:
            movement_detected = True
            
    print(json.dumps({
        "valid_json": True,
        "feature_count": feature_count,
        "max_distance_to_line": max_dist_to_line,
        "valid_geometries": valid_geoms,
        "movement_detected": movement_detected,
        "original_count": len(orig_coords)
    }))

except Exception as e:
    print(json.dumps({"valid_json": False, "error": str(e)}))
PYEOF
)
else
    ANALYSIS_JSON='{"valid_json": false, "error": "file_missing"}'
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED,
    "file_size_bytes": $FILE_SIZE,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="