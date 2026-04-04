#!/bin/bash
echo "=== Exporting network_analysis_shortest_path result ==="

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

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/GIS_Data/exports/delivery_route.geojson"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
IS_NEW="false"
GEOMETRY_ANALYSIS="{}"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        IS_NEW="true"
    fi

    # Analyze Geometry using Python
    # We check:
    # 1. Is it a LineString?
    # 2. Does it pass through the diagonal midpoint (0.5, 0.5)?
    # 3. Does it avoid the square corner (0.0, 1.0)?
    GEOMETRY_ANALYSIS=$(python3 << 'PYEOF'
import json
import math
import sys

def point_line_distance(px, py, x1, y1, x2, y2):
    # Distance from point p to line segment (x1,y1)-(x2,y2)
    # Simple projection logic
    dx = x2 - x1
    dy = y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(px - x1, py - y1)
    
    t = ((px - x1) * dx + (py - y1) * dy) / (dx*dx + dy*dy)
    t = max(0, min(1, t))
    
    proj_x = x1 + t * dx
    proj_y = y1 + t * dy
    return math.hypot(px - proj_x, py - proj_y)

try:
    with open("/home/ga/GIS_Data/exports/delivery_route.geojson") as f:
        data = json.load(f)

    features = data.get("features", [])
    if not features:
        print(json.dumps({"valid_geojson": True, "feature_count": 0}))
        sys.exit(0)
    
    # Analyze the first feature
    geom = features[0].get("geometry", {})
    gtype = geom.get("type", "")
    coords = geom.get("coordinates", [])
    
    if "LineString" not in gtype or not coords:
        print(json.dumps({"valid_geojson": True, "feature_count": len(features), "geometry_type": gtype}))
        sys.exit(0)
    
    # Flatten coords if MultiLineString (simple handling)
    if gtype == "MultiLineString":
        all_coords = [p for line in coords for p in line]
        segments = []
        for line in coords:
            for i in range(len(line)-1):
                segments.append((line[i], line[i+1]))
    else:
        all_coords = coords
        segments = []
        for i in range(len(coords)-1):
            segments.append((coords[i], coords[i+1]))
            
    # Check distances to checkpoints
    # Diagonal Midpoint (Optimal path passes here): (0.5, 0.5)
    # Corner (Sub-optimal path passes here): (0.0, 1.0)
    
    min_dist_diagonal = float('inf')
    min_dist_corner = float('inf')
    
    for p1, p2 in segments:
        d_diag = point_line_distance(0.5, 0.5, p1[0], p1[1], p2[0], p2[1])
        d_corn = point_line_distance(0.0, 1.0, p1[0], p1[1], p2[0], p2[1])
        if d_diag < min_dist_diagonal: min_dist_diagonal = d_diag
        if d_corn < min_dist_corner: min_dist_corner = d_corn
        
    print(json.dumps({
        "valid_geojson": True,
        "feature_count": len(features),
        "geometry_type": gtype,
        "dist_to_optimal": min_dist_diagonal,
        "dist_to_avoid": min_dist_corner,
        "vertex_count": len(all_coords)
    }))

except Exception as e:
    print(json.dumps({"error": str(e), "valid_geojson": False}))
PYEOF
)
else
    GEOMETRY_ANALYSIS='{"valid_geojson": false, "file_missing": true}'
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "is_new": $IS_NEW,
    "geometry_analysis": $GEOMETRY_ANALYSIS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

echo "Result:"
cat /tmp/task_result.json
echo "=== Export complete ==="