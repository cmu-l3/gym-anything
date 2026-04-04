#!/bin/bash
echo "=== Exporting Maximum Aortic CSA Result ==="

source /workspace/scripts/task_utils.sh

# Get the case ID used
if [ -f /tmp/amos_case_id ]; then
    CASE_ID=$(cat /tmp/amos_case_id)
else
    CASE_ID="amos_0001"
fi

AMOS_DIR="/home/ga/Documents/SlicerData/AMOS"
SCREENSHOTS_DIR="/home/ga/Documents/SlicerData/Screenshots"
OUTPUT_MEASUREMENT="$AMOS_DIR/max_aorta_measurement.mrk.json"
OUTPUT_REPORT="$AMOS_DIR/max_aorta_report.json"
OUTPUT_SCREENSHOT="$SCREENSHOTS_DIR/max_aorta_screenshot.png"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/max_aorta_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer before closing
    cat > /tmp/export_csa_measurements.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/AMOS"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Check for closed curve markups (used for area measurement)
curve_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsClosedCurveNode")
print(f"Found {len(curve_nodes)} closed curve markup(s)")

for node in curve_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 3:
        # Get the area measurement
        try:
            # Get curve measurements
            area = node.GetMeasurement("area").GetValue() if node.GetMeasurement("area") else 0
            
            # Get center point
            center = [0.0, 0.0, 0.0]
            for i in range(n_points):
                pos = [0.0, 0.0, 0.0]
                node.GetNthControlPointPosition(i, pos)
                center[0] += pos[0]
                center[1] += pos[1]
                center[2] += pos[2]
            center = [c / n_points for c in center]
            
            measurement = {
                "name": node.GetName(),
                "type": "closed_curve",
                "area_mm2": float(area),
                "center": center,
                "n_points": n_points
            }
            all_measurements.append(measurement)
            print(f"  Closed curve '{node.GetName()}': area={area:.1f} mm², center z={center[2]:.1f}")
        except Exception as e:
            print(f"  Error extracting curve data: {e}")

# Check for line/ruler markups as alternative
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line/ruler markup(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        # If this is a diameter measurement, estimate CSA
        estimated_csa = math.pi * (length / 2) ** 2
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": float(length),
            "estimated_csa_mm2": float(estimated_csa),
            "p1": p1,
            "p2": p2,
            "center_z": (p1[2] + p2[2]) / 2
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': length={length:.1f} mm, estimated CSA={estimated_csa:.1f} mm²")

# Check for segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for seg_node in seg_nodes:
    seg = seg_node.GetSegmentation()
    n_segs = seg.GetNumberOfSegments()
    for i in range(n_segs):
        seg_id = seg.GetNthSegmentID(i)
        segment = seg.GetSegment(seg_id)
        
        measurement = {
            "name": segment.GetName(),
            "type": "segmentation",
            "segment_id": seg_id
        }
        all_measurements.append(measurement)
        print(f"  Segment: {segment.GetName()}")

# Save all measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "max_aorta_measurement.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements, "source": "slicer_export"}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements to {meas_path}")
    
    # Also save individual markup nodes
    for node in curve_nodes:
        mrk_path = os.path.join(output_dir, f"{node.GetName()}_curve.mrk.json")
        slicer.util.saveNode(node, mrk_path)
    
    for node in line_nodes:
        mrk_path = os.path.join(output_dir, f"{node.GetName()}_line.mrk.json")
        slicer.util.saveNode(node, mrk_path)
else:
    print("No measurements found in scene")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_csa_measurements.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_csa_measurements" 2>/dev/null || true
fi

# Check if agent saved measurement file
MEASUREMENT_EXISTS="false"
MEASUREMENT_PATH=""
MEASURED_CSA=""
MEASURED_Z=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$AMOS_DIR/measurement.mrk.json"
    "$AMOS_DIR/aorta_csa.mrk.json"
    "$AMOS_DIR/aorta_measurement.mrk.json"
    "/home/ga/Documents/max_aorta_measurement.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_PATH="$path"
        echo "Found measurement at: $path"
        
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        
        # Try to extract CSA from measurement
        MEASURED_CSA=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
measurements = data.get('measurements', [])
for m in measurements:
    if m.get('type') == 'closed_curve' and m.get('area_mm2', 0) > 0:
        print(f\"{m['area_mm2']:.2f}\")
        break
    elif m.get('type') == 'line' and m.get('estimated_csa_mm2', 0) > 0:
        print(f\"{m['estimated_csa_mm2']:.2f}\")
        break
" 2>/dev/null || echo "")
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""
REPORTED_CSA=""
REPORTED_Z=""
REPORTED_DIAMETER=""
REPORTED_CLASSIFICATION=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$AMOS_DIR/aorta_report.json"
    "$AMOS_DIR/report.json"
    "$AMOS_DIR/csa_report.json"
    "/home/ga/Documents/max_aorta_report.json"
    "/home/ga/max_aorta_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_CSA=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('max_csa_mm2', d.get('csa_mm2', d.get('area_mm2', ''))))" 2>/dev/null || echo "")
        REPORTED_Z=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('slice_z_mm', d.get('z_mm', d.get('location_z', ''))))" 2>/dev/null || echo "")
        REPORTED_DIAMETER=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('equivalent_diameter_mm', d.get('diameter_mm', '')))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('clinical_assessment', d.get('classification', '')))" 2>/dev/null || echo "")
        break
    fi
done

# Check for screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_CREATED_DURING_TASK="false"

POSSIBLE_SCREENSHOT_PATHS=(
    "$OUTPUT_SCREENSHOT"
    "$SCREENSHOTS_DIR/aorta_screenshot.png"
    "$SCREENSHOTS_DIR/max_csa_screenshot.png"
    "$AMOS_DIR/screenshot.png"
    "/home/ga/Documents/max_aorta_screenshot.png"
)

for path in "${POSSIBLE_SCREENSHOT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SCREENSHOT_EXISTS="true"
        echo "Found screenshot at: $path"
        
        # Check if created during task
        SCREENSHOT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
            SCREENSHOT_CREATED_DURING_TASK="true"
        fi
        
        if [ "$path" != "$OUTPUT_SCREENSHOT" ]; then
            cp "$path" "$OUTPUT_SCREENSHOT" 2>/dev/null || true
        fi
        break
    fi
done

# Also check for any agent-created screenshots
AGENT_SCREENSHOTS=$(find "$AMOS_DIR" "$SCREENSHOTS_DIR" /home/ga/Documents -name "*.png" -newer /tmp/task_start_time_iso.txt 2>/dev/null | wc -l)
if [ "$AGENT_SCREENSHOTS" -gt 0 ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_CREATED_DURING_TASK="true"
    echo "Found $AGENT_SCREENSHOTS screenshot(s) created during task"
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${CASE_ID}_max_csa_gt.json" /tmp/max_csa_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/max_csa_ground_truth.json 2>/dev/null || true

if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/agent_measurement.json 2>/dev/null || true
    chmod 644 /tmp/agent_measurement.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_path": "$MEASUREMENT_PATH",
    "measured_csa_mm2": "$MEASURED_CSA",
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_csa_mm2": "$REPORTED_CSA",
    "reported_z_mm": "$REPORTED_Z",
    "reported_diameter_mm": "$REPORTED_DIAMETER",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "agent_screenshots_count": $AGENT_SCREENSHOTS,
    "case_id": "$CASE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/max_aorta_task_result.json 2>/dev/null || sudo rm -f /tmp/max_aorta_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/max_aorta_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/max_aorta_task_result.json
chmod 666 /tmp/max_aorta_task_result.json 2>/dev/null || sudo chmod 666 /tmp/max_aorta_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/max_aorta_task_result.json
echo ""
echo "=== Export Complete ==="