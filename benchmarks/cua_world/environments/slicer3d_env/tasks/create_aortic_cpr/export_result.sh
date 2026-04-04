#!/bin/bash
echo "=== Exporting Aortic CPR Task Result ==="

source /workspace/scripts/task_utils.sh

# Get case ID
CASE_ID=$(cat /tmp/amos_case_id 2>/dev/null || echo "amos_0001")

EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_CPR="$EXPORTS_DIR/aorta_cpr.png"
OUTPUT_CURVE="$EXPORTS_DIR/aorta_centerline.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/aortic_cpr_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export curve data from Slicer
    echo "Attempting to export curve data from Slicer..."
    cat > /tmp/export_curve.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(output_dir, exist_ok=True)

# Find curve markups
curve_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsCurveNode")
print(f"Found {len(curve_nodes)} curve markup(s)")

curves_data = []
for node in curve_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        points = []
        for i in range(n_points):
            pos = [0.0, 0.0, 0.0]
            node.GetNthControlPointPosition(i, pos)
            points.append(pos)
        
        # Calculate curve length
        total_length = 0.0
        for i in range(1, len(points)):
            p1 = points[i-1]
            p2 = points[i]
            dist = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            total_length += dist
        
        curve_info = {
            "name": node.GetName(),
            "num_points": n_points,
            "control_points": points,
            "total_length_mm": total_length
        }
        curves_data.append(curve_info)
        print(f"  Curve '{node.GetName()}': {n_points} points, {total_length:.1f} mm")
        
        # Save the curve as markup JSON
        if "aorta" in node.GetName().lower() or len(curve_nodes) == 1:
            out_path = os.path.join(output_dir, "aorta_centerline.json")
            slicer.util.saveNode(node, out_path)
            print(f"  Saved curve to {out_path}")

# Save curves summary
if curves_data:
    summary_path = os.path.join(output_dir, "curves_summary.json")
    with open(summary_path, "w") as f:
        json.dump({"curves": curves_data}, f, indent=2)
    print(f"Saved curves summary to {summary_path}")
else:
    print("No curves found in scene")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 timeout 30 /opt/Slicer/Slicer --python-script /tmp/export_curve.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# ============================================================
# Check for CPR image
# ============================================================
CPR_EXISTS="false"
CPR_SIZE_BYTES="0"
CPR_CREATED_DURING_TASK="false"
CPR_WIDTH="0"
CPR_HEIGHT="0"
CPR_UNIQUE_COLORS="0"
CPR_PATH_FOUND=""

# Search for CPR image in multiple locations
CPR_PATHS=(
    "$OUTPUT_CPR"
    "$EXPORTS_DIR/cpr.png"
    "$EXPORTS_DIR/aorta.png"
    "/home/ga/Documents/SlicerData/aorta_cpr.png"
    "/home/ga/aorta_cpr.png"
    "/home/ga/Desktop/aorta_cpr.png"
)

for path in "${CPR_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CPR_EXISTS="true"
        CPR_PATH_FOUND="$path"
        CPR_SIZE_BYTES=$(stat -c %s "$path" 2>/dev/null || echo "0")
        CPR_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$CPR_MTIME" -gt "$TASK_START" ]; then
            CPR_CREATED_DURING_TASK="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_CPR" ]; then
            cp "$path" "$OUTPUT_CPR" 2>/dev/null || true
        fi
        
        # Get image properties
        PROPS=$(python3 << PYEOF
import json
try:
    from PIL import Image
    img = Image.open("$path")
    # Sample for color count
    img_small = img.resize((100, 100)) if img.width * img.height > 10000 else img
    colors = len(set(img_small.getdata()))
    print(json.dumps({
        "width": img.width,
        "height": img.height,
        "mode": img.mode,
        "unique_colors": colors
    }))
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "mode": "", "unique_colors": 0}))
PYEOF
)
        CPR_WIDTH=$(echo "$PROPS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
        CPR_HEIGHT=$(echo "$PROPS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
        CPR_UNIQUE_COLORS=$(echo "$PROPS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('unique_colors', 0))" 2>/dev/null || echo "0")
        
        echo "Found CPR image: $path"
        echo "  Size: $CPR_SIZE_BYTES bytes, Dimensions: ${CPR_WIDTH}x${CPR_HEIGHT}, Colors: $CPR_UNIQUE_COLORS"
        break
    fi
done

# ============================================================
# Check for curve file
# ============================================================
CURVE_EXISTS="false"
CURVE_SIZE_BYTES="0"
CURVE_CREATED_DURING_TASK="false"
NUM_CONTROL_POINTS="0"
CURVE_LENGTH_MM="0"
CONTROL_POINTS_JSON="[]"
CURVE_PATH_FOUND=""

# Search for curve file
CURVE_PATHS=(
    "$OUTPUT_CURVE"
    "$EXPORTS_DIR/curve.json"
    "$EXPORTS_DIR/centerline.json"
    "$EXPORTS_DIR/curves_summary.json"
    "/home/ga/aorta_centerline.json"
    "/home/ga/Desktop/aorta_centerline.json"
)

for path in "${CURVE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CURVE_EXISTS="true"
        CURVE_PATH_FOUND="$path"
        CURVE_SIZE_BYTES=$(stat -c %s "$path" 2>/dev/null || echo "0")
        CURVE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        
        if [ "$CURVE_MTIME" -gt "$TASK_START" ]; then
            CURVE_CREATED_DURING_TASK="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_CURVE" ]; then
            cp "$path" "$OUTPUT_CURVE" 2>/dev/null || true
        fi
        
        echo "Found curve file: $path"
        
        # Parse curve data
        CURVE_INFO=$(python3 << PYEOF
import json
import math

try:
    with open("$path") as f:
        data = json.load(f)
    
    # Handle Slicer markup format
    points = []
    if "markups" in data:
        for m in data.get("markups", []):
            for cp in m.get("controlPoints", []):
                pos = cp.get("position", [0, 0, 0])
                points.append(pos)
    elif "curves" in data:
        # Summary format
        for c in data.get("curves", []):
            points = c.get("control_points", [])
            break
    elif "control_points" in data:
        points = data.get("control_points", [])
    
    # Calculate length
    total_length = 0.0
    for i in range(1, len(points)):
        p1 = points[i-1]
        p2 = points[i]
        dist = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        total_length += dist
    
    print(json.dumps({
        "num_points": len(points),
        "length_mm": round(total_length, 2),
        "points": points
    }))
except Exception as e:
    print(json.dumps({"error": str(e), "num_points": 0, "length_mm": 0, "points": []}))
PYEOF
)
        NUM_CONTROL_POINTS=$(echo "$CURVE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('num_points', 0))" 2>/dev/null || echo "0")
        CURVE_LENGTH_MM=$(echo "$CURVE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('length_mm', 0))" 2>/dev/null || echo "0")
        CONTROL_POINTS_JSON=$(echo "$CURVE_INFO" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('points', [])))" 2>/dev/null || echo "[]")
        
        echo "  Control points: $NUM_CONTROL_POINTS, Length: ${CURVE_LENGTH_MM}mm"
        break
    fi
done

# ============================================================
# Validate control points against ground truth
# ============================================================
ANATOMICAL_ALIGNMENT_SCORE="0"
POINTS_NEAR_AORTA="0"

if [ "$NUM_CONTROL_POINTS" -gt "0" ]; then
    ALIGNMENT_RESULT=$(python3 << PYEOF
import json
import math
import os

gt_dir = "$GROUND_TRUTH_DIR"
case_id = "$CASE_ID"

# Load reference aorta centerline
ref_path = os.path.join(gt_dir, f"{case_id}_aorta_ref.json")
try:
    with open(ref_path) as f:
        ref_data = json.load(f)
except:
    print(json.dumps({"alignment_score": 0, "points_near_aorta": 0, "error": "No reference"}))
    exit(0)

if not ref_data.get("has_ground_truth", False):
    print(json.dumps({"alignment_score": 50, "points_near_aorta": 0, "error": "No ground truth - giving partial credit"}))
    exit(0)

ref_points = [p["ras"] for p in ref_data.get("aorta_centerline_points", [])]

# Load agent's control points
try:
    control_points = $CONTROL_POINTS_JSON
except:
    control_points = []

if not control_points or not ref_points:
    print(json.dumps({"alignment_score": 0, "points_near_aorta": 0}))
    exit(0)

# Check how many agent points are near the aorta centerline
tolerance_mm = 15.0  # 15mm tolerance
points_near = 0

for cp in control_points:
    min_dist = float('inf')
    for rp in ref_points:
        dist = math.sqrt(sum((a-b)**2 for a,b in zip(cp, rp)))
        min_dist = min(min_dist, dist)
    if min_dist <= tolerance_mm:
        points_near += 1

alignment_pct = (points_near / len(control_points)) * 100 if control_points else 0

print(json.dumps({
    "alignment_score": round(alignment_pct, 1),
    "points_near_aorta": points_near,
    "total_points": len(control_points),
    "tolerance_mm": tolerance_mm
}))
PYEOF
)
    ANATOMICAL_ALIGNMENT_SCORE=$(echo "$ALIGNMENT_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('alignment_score', 0))" 2>/dev/null || echo "0")
    POINTS_NEAR_AORTA=$(echo "$ALIGNMENT_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('points_near_aorta', 0))" 2>/dev/null || echo "0")
    echo "Anatomical alignment: ${ANATOMICAL_ALIGNMENT_SCORE}% (${POINTS_NEAR_AORTA}/${NUM_CONTROL_POINTS} points near aorta)"
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "case_id": "$CASE_ID",
    "slicer_was_running": $SLICER_RUNNING,
    "cpr_image": {
        "exists": $CPR_EXISTS,
        "path_found": "$CPR_PATH_FOUND",
        "size_bytes": $CPR_SIZE_BYTES,
        "created_during_task": $CPR_CREATED_DURING_TASK,
        "width": $CPR_WIDTH,
        "height": $CPR_HEIGHT,
        "unique_colors": $CPR_UNIQUE_COLORS
    },
    "curve": {
        "exists": $CURVE_EXISTS,
        "path_found": "$CURVE_PATH_FOUND",
        "size_bytes": $CURVE_SIZE_BYTES,
        "created_during_task": $CURVE_CREATED_DURING_TASK,
        "num_control_points": $NUM_CONTROL_POINTS,
        "length_mm": $CURVE_LENGTH_MM,
        "control_points": $CONTROL_POINTS_JSON
    },
    "validation": {
        "anatomical_alignment_pct": $ANATOMICAL_ALIGNMENT_SCORE,
        "points_near_aorta": $POINTS_NEAR_AORTA
    },
    "screenshot_path": "/tmp/aortic_cpr_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/aortic_cpr_result.json 2>/dev/null || sudo rm -f /tmp/aortic_cpr_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/aortic_cpr_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/aortic_cpr_result.json
chmod 666 /tmp/aortic_cpr_result.json 2>/dev/null || sudo chmod 666 /tmp/aortic_cpr_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/aortic_cpr_result.json"
cat /tmp/aortic_cpr_result.json
echo ""
echo "=== Export Complete ==="