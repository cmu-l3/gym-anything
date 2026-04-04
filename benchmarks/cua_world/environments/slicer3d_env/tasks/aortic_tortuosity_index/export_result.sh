#!/bin/bash
echo "=== Exporting Aortic Tortuosity Index Result ==="

source /workspace/scripts/task_utils.sh

# Get case ID
if [ -f /tmp/tortuosity_case_id ]; then
    CASE_ID=$(cat /tmp/tortuosity_case_id)
else
    CASE_ID="amos_tortuous_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
OUTPUT_CENTERLINE="$AMOS_DIR/aorta_centerline.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/tortuosity_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/tortuosity_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export markups from Slicer
    cat > /tmp/export_centerline.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

centerline_points = []

# Check for fiducial markups
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial markup node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{node.GetName()}': {n_points} points")
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        centerline_points.append({
            "label": label,
            "position_mm": pos
        })
        print(f"    Point {i}: {pos}")

# Also check for curve markups
curve_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsCurveNode")
print(f"Found {len(curve_nodes)} curve markup node(s)")

for node in curve_nodes:
    n_points = node.GetNumberOfControlPoints()
    print(f"  Curve '{node.GetName()}': {n_points} control points")
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        centerline_points.append({
            "label": f"curve_pt_{i}",
            "position_mm": pos
        })

# Calculate measurements if we have enough points
if len(centerline_points) >= 2:
    # Sort by z-coordinate (superior to inferior)
    centerline_points.sort(key=lambda p: p["position_mm"][2], reverse=True)
    
    # Chord length
    first_pt = centerline_points[0]["position_mm"]
    last_pt = centerline_points[-1]["position_mm"]
    chord_length = math.sqrt(sum((a-b)**2 for a,b in zip(first_pt, last_pt)))
    
    # Arc length
    arc_length = 0.0
    for i in range(1, len(centerline_points)):
        p1 = centerline_points[i-1]["position_mm"]
        p2 = centerline_points[i]["position_mm"]
        arc_length += math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
    
    # Tortuosity Index
    if chord_length > 0:
        ti = ((arc_length - chord_length) / chord_length) * 100.0
    else:
        ti = 0.0
    
    # Classification
    if ti < 10:
        classification = "Normal"
    elif ti < 20:
        classification = "Mild Tortuosity"
    elif ti < 35:
        classification = "Moderate Tortuosity"
    else:
        classification = "Severe Tortuosity"
    
    print(f"\nCalculated measurements:")
    print(f"  Chord Length: {chord_length:.2f} mm")
    print(f"  Arc Length: {arc_length:.2f} mm")
    print(f"  Tortuosity Index: {ti:.2f}%")
    print(f"  Classification: {classification}")
    
    # Save centerline
    centerline_data = {
        "centerline_points": centerline_points,
        "num_points": len(centerline_points),
        "measurements": {
            "chord_length_mm": chord_length,
            "arc_length_mm": arc_length,
            "tortuosity_index_percent": ti,
            "classification": classification
        }
    }
    
    centerline_path = os.path.join(output_dir, "aorta_centerline.mrk.json")
    with open(centerline_path, "w") as f:
        json.dump(centerline_data, f, indent=2)
    print(f"\nCenterline saved to: {centerline_path}")
    
else:
    print("Not enough centerline points found to calculate measurements")

# Also save any markup nodes directly
for node in fid_nodes + curve_nodes:
    try:
        node_name = node.GetName().replace(" ", "_")
        mrk_path = os.path.join(output_dir, f"{node_name}.mrk.json")
        slicer.util.saveNode(node, mrk_path)
        print(f"Saved markup node to: {mrk_path}")
    except Exception as e:
        print(f"Could not save node: {e}")

print("\nExport complete")
PYEOF

    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_centerline.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_centerline" 2>/dev/null || true
fi

# Check for centerline file
CENTERLINE_EXISTS="false"
CENTERLINE_PATH=""
NUM_POINTS=0
AGENT_CHORD=""
AGENT_ARC=""
AGENT_TI=""
AGENT_CLASS=""

POSSIBLE_CENTERLINE_PATHS=(
    "$OUTPUT_CENTERLINE"
    "$AMOS_DIR/aorta_centerline.mrk.json"
    "$AMOS_DIR/centerline.mrk.json"
    "$AMOS_DIR/F.mrk.json"
    "/home/ga/Documents/aorta_centerline.mrk.json"
)

for path in "${POSSIBLE_CENTERLINE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CENTERLINE_EXISTS="true"
        CENTERLINE_PATH="$path"
        echo "Found centerline at: $path"
        
        if [ "$path" != "$OUTPUT_CENTERLINE" ]; then
            cp "$path" "$OUTPUT_CENTERLINE" 2>/dev/null || true
        fi
        
        # Extract data from centerline file
        NUM_POINTS=$(python3 -c "
import json
try:
    with open('$path') as f:
        data = json.load(f)
    pts = data.get('centerline_points', data.get('markups', []))
    if isinstance(pts, list):
        print(len(pts))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null || echo "0")
        
        # Try to get measurements
        AGENT_CHORD=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
m = data.get('measurements', {})
print(m.get('chord_length_mm', ''))
" 2>/dev/null || echo "")
        
        AGENT_ARC=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
m = data.get('measurements', {})
print(m.get('arc_length_mm', ''))
" 2>/dev/null || echo "")
        
        AGENT_TI=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
m = data.get('measurements', {})
print(m.get('tortuosity_index_percent', ''))
" 2>/dev/null || echo "")
        
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/tortuosity_report.json"
    "$AMOS_DIR/report.json"
    "/home/ga/Documents/tortuosity_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract values from report if not already got from centerline
        if [ -z "$AGENT_CHORD" ]; then
            AGENT_CHORD=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
print(data.get('chord_length_mm', ''))
" 2>/dev/null || echo "")
        fi
        
        if [ -z "$AGENT_ARC" ]; then
            AGENT_ARC=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
print(data.get('arc_length_mm', ''))
" 2>/dev/null || echo "")
        fi
        
        if [ -z "$AGENT_TI" ]; then
            AGENT_TI=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
print(data.get('tortuosity_index_percent', ''))
" 2>/dev/null || echo "")
        fi
        
        AGENT_CLASS=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
print(data.get('classification', ''))
" 2>/dev/null || echo "")
        
        break
    fi
done

# Check file timestamps for anti-gaming
FILE_CREATED_DURING_TASK="false"
if [ "$CENTERLINE_EXISTS" = "true" ] && [ -f "$OUTPUT_CENTERLINE" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_CENTERLINE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/${CASE_ID}_tortuosity_gt.json" /tmp/tortuosity_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/tortuosity_ground_truth.json 2>/dev/null || true

# Copy agent files
if [ -f "$OUTPUT_CENTERLINE" ]; then
    cp "$OUTPUT_CENTERLINE" /tmp/agent_centerline.json 2>/dev/null || true
    chmod 644 /tmp/agent_centerline.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

# Close Slicer
echo "Closing Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "centerline_exists": $CENTERLINE_EXISTS,
    "centerline_path": "$CENTERLINE_PATH",
    "num_centerline_points": $NUM_POINTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "agent_measurements": {
        "chord_length_mm": "$AGENT_CHORD",
        "arc_length_mm": "$AGENT_ARC",
        "tortuosity_index_percent": "$AGENT_TI",
        "classification": "$AGENT_CLASS"
    },
    "screenshot_exists": $([ -f "/tmp/tortuosity_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/tortuosity_ground_truth.json" ] && echo "true" || echo "false"),
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/tortuosity_task_result.json 2>/dev/null || sudo rm -f /tmp/tortuosity_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/tortuosity_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/tortuosity_task_result.json
chmod 666 /tmp/tortuosity_task_result.json 2>/dev/null || sudo chmod 666 /tmp/tortuosity_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/tortuosity_task_result.json
echo ""
echo "=== Export Complete ==="