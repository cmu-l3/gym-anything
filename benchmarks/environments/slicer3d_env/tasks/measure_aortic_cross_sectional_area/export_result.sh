#!/bin/bash
echo "=== Exporting Aortic Cross-Sectional Area Measurement Result ==="

source /workspace/scripts/task_utils.sh

CASE_ID="amos_0001"
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_REPORT="$EXPORTS_DIR/aortic_area_measurement.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot FIRST (captures current state)
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
sleep 1

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# ============================================================
# Try to extract measurements from Slicer via Python script
# ============================================================
echo "Attempting to extract measurements from Slicer..."

cat > /tmp/extract_aortic_measurements.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/Exports"
os.makedirs(output_dir, exist_ok=True)

# Look for closed curve markups
curve_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsCurveNode")
print(f"Found {len(curve_nodes)} curve markup(s)")

measurements = []
best_curve = None
best_area = 0

for node in curve_nodes:
    is_closed = node.GetCurveClosed()
    n_points = node.GetNumberOfControlPoints()
    name = node.GetName()
    
    print(f"  Curve '{name}': {n_points} points, closed={is_closed}")
    
    if is_closed and n_points >= 4:
        # Get the curve's measurements - area is computed by Slicer for closed curves
        # The measurement is stored in the curve node
        
        # Get control points to calculate z-level
        z_coords = []
        for i in range(n_points):
            pos = [0.0, 0.0, 0.0]
            node.GetNthControlPointPosition(i, pos)
            z_coords.append(pos[2])
        
        avg_z = sum(z_coords) / len(z_coords) if z_coords else 0
        
        # Calculate area using the curve's built-in measurement
        # Get the curve area from Slicer's measurement framework
        area = 0.0
        try:
            # For closed curves, we can compute area from the polygon
            # Get all curve points (interpolated, not just control points)
            curve_points = []
            for i in range(node.GetNumberOfControlPoints()):
                pos = [0.0, 0.0, 0.0]
                node.GetNthControlPointPosition(i, pos)
                curve_points.append(pos)
            
            if len(curve_points) >= 3:
                # Calculate area using Shoelace formula (2D projection)
                # Assuming the curve is approximately planar in axial view
                x_coords = [p[0] for p in curve_points]
                y_coords = [p[1] for p in curve_points]
                
                n = len(curve_points)
                area = 0.0
                for i in range(n):
                    j = (i + 1) % n
                    area += x_coords[i] * y_coords[j]
                    area -= x_coords[j] * y_coords[i]
                area = abs(area) / 2.0
                
                print(f"    Calculated area: {area:.2f} mm²")
        except Exception as e:
            print(f"    Error calculating area: {e}")
        
        measurement = {
            "name": name,
            "num_control_points": n_points,
            "is_closed": is_closed,
            "area_mm2": area,
            "avg_z_coord": avg_z
        }
        measurements.append(measurement)
        
        if area > best_area:
            best_area = area
            best_curve = measurement

# Save all curve measurements
all_meas_path = os.path.join(output_dir, "all_curve_measurements.json")
with open(all_meas_path, "w") as f:
    json.dump({"curves": measurements, "best_curve": best_curve}, f, indent=2)

print(f"Exported {len(measurements)} curve measurements")
if best_curve:
    print(f"Best curve: {best_curve['name']} with area {best_curve['area_mm2']:.2f} mm²")
PYEOF

if [ "$SLICER_RUNNING" = "true" ]; then
    # Run extraction script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/extract_aortic_measurements.py --no-main-window > /tmp/slicer_extract.log 2>&1 &
    sleep 8
    pkill -f "extract_aortic_measurements" 2>/dev/null || true
fi

# ============================================================
# Check for output files
# ============================================================
echo "Checking for output files..."

REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
EXTRACTED_AREA=""
EXTRACTED_SLICE=""
EXTRACTED_POINTS=""
EXTRACTED_NAME=""

# Check agent's output file
if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
        echo "Output report found and created during task"
    else
        echo "Output report exists but was created before task start"
    fi
    
    # Extract values from agent's report
    EXTRACTED_AREA=$(python3 -c "
import json
try:
    with open('$OUTPUT_REPORT') as f:
        data = json.load(f)
    area = data.get('cross_sectional_area_mm2', 0)
    print(f'{area:.2f}' if area else '')
except Exception as e:
    print('')
" 2>/dev/null || echo "")
    
    EXTRACTED_SLICE=$(python3 -c "
import json
try:
    with open('$OUTPUT_REPORT') as f:
        data = json.load(f)
    print(data.get('slice_index', ''))
except:
    print('')
" 2>/dev/null || echo "")
    
    EXTRACTED_POINTS=$(python3 -c "
import json
try:
    with open('$OUTPUT_REPORT') as f:
        data = json.load(f)
    print(data.get('num_control_points', ''))
except:
    print('')
" 2>/dev/null || echo "")
    
    EXTRACTED_NAME=$(python3 -c "
import json
try:
    with open('$OUTPUT_REPORT') as f:
        data = json.load(f)
    print(data.get('curve_name', ''))
except:
    print('')
" 2>/dev/null || echo "")
    
    echo "  Extracted area: $EXTRACTED_AREA mm²"
    echo "  Extracted slice: $EXTRACTED_SLICE"
    echo "  Extracted control points: $EXTRACTED_POINTS"
else
    echo "Output report not found at $OUTPUT_REPORT"
fi

# Also check Slicer's extracted measurements
SLICER_CURVE_AREA=""
SLICER_CURVE_POINTS=""
SLICER_CURVE_Z=""

EXTRACTED_CURVES="$EXPORTS_DIR/all_curve_measurements.json"
if [ -f "$EXTRACTED_CURVES" ]; then
    echo "Found Slicer curve measurements"
    SLICER_CURVE_AREA=$(python3 -c "
import json
try:
    with open('$EXTRACTED_CURVES') as f:
        data = json.load(f)
    if data.get('best_curve'):
        print(f\"{data['best_curve'].get('area_mm2', 0):.2f}\")
except:
    print('')
" 2>/dev/null || echo "")
    
    SLICER_CURVE_POINTS=$(python3 -c "
import json
try:
    with open('$EXTRACTED_CURVES') as f:
        data = json.load(f)
    if data.get('best_curve'):
        print(data['best_curve'].get('num_control_points', 0))
except:
    print('')
" 2>/dev/null || echo "")
    
    SLICER_CURVE_Z=$(python3 -c "
import json
try:
    with open('$EXTRACTED_CURVES') as f:
        data = json.load(f)
    if data.get('best_curve'):
        print(f\"{data['best_curve'].get('avg_z_coord', 0):.1f}\")
except:
    print('')
" 2>/dev/null || echo "")
    
    echo "  Slicer extracted area: $SLICER_CURVE_AREA mm²"
    echo "  Slicer extracted points: $SLICER_CURVE_POINTS"
    echo "  Slicer extracted z: $SLICER_CURVE_Z"
fi

# ============================================================
# Load ground truth for comparison
# ============================================================
GT_MAX_SLICE=""
GT_EXPECTED_AREA=""
GT_DIAMETER=""

GT_FILE="/tmp/aorta_ground_truth.json"
if [ -f "$GT_FILE" ]; then
    GT_MAX_SLICE=$(python3 -c "
import json
try:
    with open('$GT_FILE') as f:
        data = json.load(f)
    print(data.get('max_slice_index', data.get('aorta_max_slice_index', '')))
except:
    print('')
" 2>/dev/null || echo "")
    
    GT_DIAMETER=$(python3 -c "
import json
import math
try:
    with open('$GT_FILE') as f:
        data = json.load(f)
    diam = data.get('max_diameter_mm', data.get('aorta_max_diameter_mm', 0))
    print(f'{diam:.2f}')
except:
    print('')
" 2>/dev/null || echo "")
    
    # Calculate expected area from diameter
    if [ -n "$GT_DIAMETER" ] && [ "$GT_DIAMETER" != "0" ] && [ "$GT_DIAMETER" != "0.00" ]; then
        GT_EXPECTED_AREA=$(python3 -c "
import math
diam = float('$GT_DIAMETER')
area = math.pi * (diam / 2.0) ** 2
print(f'{area:.2f}')
" 2>/dev/null || echo "")
    fi
    
    echo "Ground truth - max slice: $GT_MAX_SLICE, diameter: $GT_DIAMETER mm, expected area: $GT_EXPECTED_AREA mm²"
fi

# ============================================================
# Check for any closed curves in the scene (backup check)
# ============================================================
CURVE_EXISTS="false"
if [ -f "$EXTRACTED_CURVES" ]; then
    CURVE_COUNT=$(python3 -c "
import json
try:
    with open('$EXTRACTED_CURVES') as f:
        data = json.load(f)
    curves = data.get('curves', [])
    closed_curves = [c for c in curves if c.get('is_closed', False)]
    print(len(closed_curves))
except:
    print(0)
" 2>/dev/null || echo "0")
    
    if [ "$CURVE_COUNT" -gt 0 ]; then
        CURVE_EXISTS="true"
    fi
fi

# ============================================================
# Create result JSON for verifier
# ============================================================
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "curve_exists_in_scene": $CURVE_EXISTS,
    "extracted_area_mm2": "$EXTRACTED_AREA",
    "extracted_slice_index": "$EXTRACTED_SLICE",
    "extracted_num_control_points": "$EXTRACTED_POINTS",
    "extracted_curve_name": "$EXTRACTED_NAME",
    "slicer_curve_area_mm2": "$SLICER_CURVE_AREA",
    "slicer_curve_num_points": "$SLICER_CURVE_POINTS",
    "slicer_curve_z_coord": "$SLICER_CURVE_Z",
    "gt_max_slice_index": "$GT_MAX_SLICE",
    "gt_expected_area_mm2": "$GT_EXPECTED_AREA",
    "gt_diameter_mm": "$GT_DIAMETER",
    "screenshot_final_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/aortic_area_task_result.json 2>/dev/null || sudo rm -f /tmp/aortic_area_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/aortic_area_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/aortic_area_task_result.json
chmod 666 /tmp/aortic_area_task_result.json 2>/dev/null || sudo chmod 666 /tmp/aortic_area_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/aortic_area_task_result.json"
cat /tmp/aortic_area_task_result.json
echo ""
echo "=== Export Complete ==="