#!/bin/bash
echo "=== Exporting Create Closed Curve ROI Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# Initialize result variables
CLOSED_CURVE_EXISTS="false"
CURVE_NAME=""
CONTROL_POINT_COUNT=0
CURVE_IS_CLOSED="false"
CURVE_CENTROID_RAS="[0, 0, 0]"
CURVE_PERIMETER_MM=0
CURVE_AREA_MM2=0
CURVE_Z_COORD=0
ALL_CURVES="[]"

# Extract closed curve data from Slicer using Python API
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting closed curve data from Slicer..."
    
    cat > /tmp/export_closed_curve.py << 'PYEOF'
import slicer
import json
import math
import os

output_data = {
    "closed_curve_exists": False,
    "curve_name": "",
    "control_point_count": 0,
    "curve_is_closed": False,
    "curve_centroid_ras": [0, 0, 0],
    "curve_perimeter_mm": 0,
    "curve_area_mm2": 0,
    "curve_z_coord": 0,
    "all_curves": [],
    "all_markups": []
}

# Get all markup nodes
all_markups = []
for node_type in ["vtkMRMLMarkupsFiducialNode", "vtkMRMLMarkupsLineNode", 
                   "vtkMRMLMarkupsClosedCurveNode", "vtkMRMLMarkupsCurveNode"]:
    nodes = slicer.util.getNodesByClass(node_type)
    for node in nodes:
        markup_info = {
            "name": node.GetName(),
            "type": node_type.replace("vtkMRMLMarkups", "").replace("Node", ""),
            "point_count": node.GetNumberOfControlPoints()
        }
        all_markups.append(markup_info)

output_data["all_markups"] = all_markups
print(f"Found {len(all_markups)} total markup nodes")

# Specifically look for closed curves
closed_curve_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsClosedCurveNode")
print(f"Found {len(closed_curve_nodes)} closed curve node(s)")

curves_data = []
best_curve = None
best_point_count = 0

for node in closed_curve_nodes:
    n_points = node.GetNumberOfControlPoints()
    name = node.GetName()
    
    # Get control points
    points = []
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        points.append(pos)
    
    # Calculate centroid
    if points:
        centroid = [sum(p[i] for p in points) / len(points) for i in range(3)]
    else:
        centroid = [0, 0, 0]
    
    # Calculate perimeter (sum of distances between consecutive points)
    perimeter = 0.0
    if len(points) > 1:
        for i in range(len(points)):
            p1 = points[i]
            p2 = points[(i + 1) % len(points)]  # Wrap around for closed curve
            dist = math.sqrt(sum((a - b)**2 for a, b in zip(p1, p2)))
            perimeter += dist
    
    # Estimate average z coordinate
    avg_z = sum(p[2] for p in points) / len(points) if points else 0
    
    curve_info = {
        "name": name,
        "control_points": n_points,
        "centroid_ras": centroid,
        "perimeter_mm": perimeter,
        "avg_z_ras": avg_z,
        "points": points[:5] if len(points) > 5 else points  # First 5 points for debugging
    }
    curves_data.append(curve_info)
    
    print(f"  Curve '{name}': {n_points} points, centroid={centroid}, perimeter={perimeter:.1f}mm")
    
    # Track best curve (most control points)
    if n_points > best_point_count:
        best_point_count = n_points
        best_curve = {
            "node": node,
            "name": name,
            "points": points,
            "centroid": centroid,
            "perimeter": perimeter,
            "avg_z": avg_z
        }

output_data["all_curves"] = curves_data

# Set output based on best curve found
if best_curve and best_point_count > 0:
    output_data["closed_curve_exists"] = True
    output_data["curve_name"] = best_curve["name"]
    output_data["control_point_count"] = best_point_count
    output_data["curve_is_closed"] = True  # ClosedCurve nodes are always closed
    output_data["curve_centroid_ras"] = best_curve["centroid"]
    output_data["curve_perimeter_mm"] = best_curve["perimeter"]
    output_data["curve_z_coord"] = best_curve["avg_z"]
    
    # Estimate area using shoelace formula (2D projection in axial plane)
    points_2d = [(p[0], p[1]) for p in best_curve["points"]]
    if len(points_2d) >= 3:
        # Shoelace formula
        n = len(points_2d)
        area = 0.0
        for i in range(n):
            j = (i + 1) % n
            area += points_2d[i][0] * points_2d[j][1]
            area -= points_2d[j][0] * points_2d[i][1]
        area = abs(area) / 2.0
        output_data["curve_area_mm2"] = area

# Save to file
output_path = "/tmp/closed_curve_data.json"
with open(output_path, "w") as f:
    json.dump(output_data, f, indent=2)

print(f"Closed curve data exported to {output_path}")
print(f"Best curve: {output_data.get('curve_name', 'None')} with {output_data.get('control_point_count', 0)} points")
PYEOF

    # Run the export script in Slicer
    # Try to use Slicer's Python to run the script
    timeout 30 /opt/Slicer/bin/PythonSlicer /tmp/export_closed_curve.py > /tmp/slicer_export.log 2>&1 || {
        echo "Direct Python execution failed, trying via Slicer..."
        # Alternative: run via Slicer's exec method
        DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/export_closed_curve.py >> /tmp/slicer_export.log 2>&1 &
        EXPORT_PID=$!
        sleep 15
        kill $EXPORT_PID 2>/dev/null || true
    }
    
    # Read exported data if available
    if [ -f /tmp/closed_curve_data.json ]; then
        echo "Reading exported closed curve data..."
        CLOSED_CURVE_EXISTS=$(python3 -c "import json; print('true' if json.load(open('/tmp/closed_curve_data.json')).get('closed_curve_exists', False) else 'false')" 2>/dev/null || echo "false")
        CURVE_NAME=$(python3 -c "import json; print(json.load(open('/tmp/closed_curve_data.json')).get('curve_name', ''))" 2>/dev/null || echo "")
        CONTROL_POINT_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/closed_curve_data.json')).get('control_point_count', 0))" 2>/dev/null || echo "0")
        CURVE_IS_CLOSED=$(python3 -c "import json; print('true' if json.load(open('/tmp/closed_curve_data.json')).get('curve_is_closed', False) else 'false')" 2>/dev/null || echo "false")
        CURVE_CENTROID_RAS=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/closed_curve_data.json')).get('curve_centroid_ras', [0,0,0])))" 2>/dev/null || echo "[0, 0, 0]")
        CURVE_PERIMETER_MM=$(python3 -c "import json; print(json.load(open('/tmp/closed_curve_data.json')).get('curve_perimeter_mm', 0))" 2>/dev/null || echo "0")
        CURVE_AREA_MM2=$(python3 -c "import json; print(json.load(open('/tmp/closed_curve_data.json')).get('curve_area_mm2', 0))" 2>/dev/null || echo "0")
        CURVE_Z_COORD=$(python3 -c "import json; print(json.load(open('/tmp/closed_curve_data.json')).get('curve_z_coord', 0))" 2>/dev/null || echo "0")
        ALL_CURVES=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/closed_curve_data.json')).get('all_curves', [])))" 2>/dev/null || echo "[]")
    else
        echo "WARNING: Closed curve data file not found"
    fi
fi

# Load tumor reference data
TUMOR_EXISTS="false"
TUMOR_CENTROID_RAS="[0, 0, 0]"
TUMOR_BBOX_MIN="[0, 0, 0]"
TUMOR_BBOX_MAX="[0, 0, 0]"

if [ -f /tmp/tumor_reference.json ]; then
    TUMOR_EXISTS=$(python3 -c "import json; print('true' if json.load(open('/tmp/tumor_reference.json')).get('tumor_exists', False) else 'false')" 2>/dev/null || echo "false")
    TUMOR_CENTROID_RAS=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/tumor_reference.json')).get('tumor_centroid_ras', [0,0,0])))" 2>/dev/null || echo "[0, 0, 0]")
    TUMOR_BBOX_MIN=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/tumor_reference.json')).get('tumor_bbox_min_ras', [0,0,0])))" 2>/dev/null || echo "[0, 0, 0]")
    TUMOR_BBOX_MAX=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/tumor_reference.json')).get('tumor_bbox_max_ras', [0,0,0])))" 2>/dev/null || echo "[0, 0, 0]")
fi

# Check if curve was created during task (not pre-existing)
CURVE_CREATED_DURING_TASK="false"
INITIAL_CURVE_COUNT=$(cat /tmp/initial_curve_count.txt 2>/dev/null || echo "0")
if [ "$CLOSED_CURVE_EXISTS" = "true" ] && [ "$INITIAL_CURVE_COUNT" = "0" ]; then
    CURVE_CREATED_DURING_TASK="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sample_id": "$SAMPLE_ID",
    "slicer_was_running": $SLICER_RUNNING,
    "closed_curve_exists": $CLOSED_CURVE_EXISTS,
    "curve_name": "$CURVE_NAME",
    "control_point_count": $CONTROL_POINT_COUNT,
    "curve_is_closed": $CURVE_IS_CLOSED,
    "curve_centroid_ras": $CURVE_CENTROID_RAS,
    "curve_perimeter_mm": $CURVE_PERIMETER_MM,
    "curve_area_mm2": $CURVE_AREA_MM2,
    "curve_z_coord": $CURVE_Z_COORD,
    "curve_created_during_task": $CURVE_CREATED_DURING_TASK,
    "tumor_exists": $TUMOR_EXISTS,
    "tumor_centroid_ras": $TUMOR_CENTROID_RAS,
    "tumor_bbox_min_ras": $TUMOR_BBOX_MIN,
    "tumor_bbox_max_ras": $TUMOR_BBOX_MAX,
    "all_curves": $ALL_CURVES,
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/closed_curve_result.json 2>/dev/null || sudo rm -f /tmp/closed_curve_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/closed_curve_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/closed_curve_result.json
chmod 666 /tmp/closed_curve_result.json 2>/dev/null || sudo chmod 666 /tmp/closed_curve_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/closed_curve_result.json
echo ""
echo "=== Export Complete ==="