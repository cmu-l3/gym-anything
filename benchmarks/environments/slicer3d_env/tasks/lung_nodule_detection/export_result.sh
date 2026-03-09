#!/bin/bash
echo "=== Exporting Lung Nodule Detection Result ==="

source /workspace/scripts/task_utils.sh

# Get the patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_FIDUCIALS="$LIDC_DIR/agent_fiducials.fcsv"
OUTPUT_REPORT="$LIDC_DIR/nodule_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/lidc_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"

    # Try to export fiducials from Slicer before closing
    cat > /tmp/export_fiducials.py << 'PYEOF'
import slicer
import os

output_dir = "/home/ga/Documents/SlicerData/LIDC"
os.makedirs(output_dir, exist_ok=True)

# Find all fiducial/markup nodes
markup_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(markup_nodes)} fiducial node(s)")

all_points = []
for node in markup_nodes:
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{node.GetName()}': {n_points} points")
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        all_points.append({"label": label, "position": pos})

# Export as .fcsv if points exist
if markup_nodes:
    # Use Slicer's built-in export
    fcsv_path = os.path.join(output_dir, "agent_fiducials.fcsv")
    slicer.util.saveNode(markup_nodes[0], fcsv_path)
    print(f"Exported fiducials to {fcsv_path}")

    # Also save all points as JSON
    import json
    json_path = os.path.join(output_dir, "exported_fiducials.json")
    with open(json_path, "w") as f:
        json.dump({"total_points": len(all_points), "points": all_points}, f, indent=2)
    print(f"Exported {len(all_points)} points to JSON")
else:
    print("No fiducial nodes found in scene")

# Also check for ruler/line markups (agent might use rulers for diameter)
ruler_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
if ruler_nodes:
    print(f"Found {len(ruler_nodes)} ruler/line markup(s)")
    measurements = []
    for node in ruler_nodes:
        if node.GetNumberOfControlPoints() >= 2:
            p1 = [0.0, 0.0, 0.0]
            p2 = [0.0, 0.0, 0.0]
            node.GetNthControlPointPosition(0, p1)
            node.GetNthControlPointPosition(1, p2)
            import math
            length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            measurements.append({
                "name": node.GetName(),
                "length_mm": length,
                "p1": p1,
                "p2": p2,
            })
    if measurements:
        import json
        meas_path = os.path.join(output_dir, "measurements.json")
        with open(meas_path, "w") as f:
            json.dump(measurements, f, indent=2)
        print(f"Exported {len(measurements)} measurements")

print("Export complete")
PYEOF

    # Run the export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_fiducials.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_fiducials" 2>/dev/null || true
fi

# Check if agent saved fiducials
FIDUCIALS_EXIST="false"
FIDUCIAL_COUNT=0
FIDUCIALS_PATH=""

# Check multiple possible locations
POSSIBLE_FCSV_PATHS=(
    "$OUTPUT_FIDUCIALS"
    "$LIDC_DIR/agent_fiducials.fcsv"
    "$LIDC_DIR/F.fcsv"
    "$LIDC_DIR/Fiducials.fcsv"
    "$LIDC_DIR/MarkupsFiducial.fcsv"
    "/home/ga/Documents/agent_fiducials.fcsv"
    "/home/ga/agent_fiducials.fcsv"
)

for path in "${POSSIBLE_FCSV_PATHS[@]}"; do
    if [ -f "$path" ]; then
        FIDUCIALS_EXIST="true"
        FIDUCIALS_PATH="$path"
        # Count non-comment lines (each is a fiducial point)
        FIDUCIAL_COUNT=$(grep -v "^#" "$path" | grep -c "," || echo "0")
        echo "Found fiducials at: $path ($FIDUCIAL_COUNT points)"
        if [ "$path" != "$OUTPUT_FIDUCIALS" ]; then
            cp "$path" "$OUTPUT_FIDUCIALS" 2>/dev/null || true
        fi
        break
    fi
done

# Check if agent saved a report
REPORT_EXISTS="false"
REPORT_PATH=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/nodule_report.json"
    "$LIDC_DIR/report.json"
    "$LIDC_DIR/nodule_report.txt"
    "/home/ga/Documents/nodule_report.json"
    "/home/ga/nodule_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Check for exported fiducials JSON (from Slicer export script)
EXPORTED_FIDUCIALS_JSON="$LIDC_DIR/exported_fiducials.json"
EXPORTED_FIDUCIALS_EXIST="false"
if [ -f "$EXPORTED_FIDUCIALS_JSON" ]; then
    EXPORTED_FIDUCIALS_EXIST="true"
fi

# Check for measurements
MEASUREMENTS_EXIST="false"
if [ -f "$LIDC_DIR/measurements.json" ]; then
    MEASUREMENTS_EXIST="true"
fi

# Check if agent adjusted window/level (by checking screenshots for lung window)
SCREENSHOTS_COUNT=$(find "$LIDC_DIR" /home/ga/Documents -name "*.png" -newer /tmp/task_start_time 2>/dev/null | wc -l)

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_nodules.json" /tmp/ground_truth_nodules.json 2>/dev/null || true
chmod 644 /tmp/ground_truth_nodules.json 2>/dev/null || true

if [ -f "$OUTPUT_FIDUCIALS" ]; then
    cp "$OUTPUT_FIDUCIALS" /tmp/agent_fiducials.fcsv 2>/dev/null || true
    chmod 644 /tmp/agent_fiducials.fcsv 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_nodule_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_nodule_report.json 2>/dev/null || true
fi

if [ -f "$EXPORTED_FIDUCIALS_JSON" ]; then
    cp "$EXPORTED_FIDUCIALS_JSON" /tmp/exported_fiducials.json 2>/dev/null || true
    chmod 644 /tmp/exported_fiducials.json 2>/dev/null || true
fi

if [ -f "$LIDC_DIR/measurements.json" ]; then
    cp "$LIDC_DIR/measurements.json" /tmp/agent_measurements.json 2>/dev/null || true
    chmod 644 /tmp/agent_measurements.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "fiducials_exist": $FIDUCIALS_EXIST,
    "fiducials_path": "$FIDUCIALS_PATH",
    "fiducial_count": $FIDUCIAL_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "exported_fiducials_exist": $EXPORTED_FIDUCIALS_EXIST,
    "measurements_exist": $MEASUREMENTS_EXIST,
    "screenshots_count": $SCREENSHOTS_COUNT,
    "screenshot_exists": $([ -f "/tmp/lidc_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/ground_truth_nodules.json" ] && echo "true" || echo "false"),
    "patient_id": "$PATIENT_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/lidc_task_result.json 2>/dev/null || sudo rm -f /tmp/lidc_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/lidc_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/lidc_task_result.json
chmod 666 /tmp/lidc_task_result.json 2>/dev/null || sudo chmod 666 /tmp/lidc_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/lidc_task_result.json
echo ""
echo "=== Export Complete ==="
