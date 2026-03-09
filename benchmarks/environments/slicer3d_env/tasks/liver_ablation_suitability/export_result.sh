#!/bin/bash
echo "=== Exporting Liver Ablation Suitability Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Configuration
IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MEASUREMENT="$IRCADB_DIR/lesion_measurements.mrk.json"
OUTPUT_REPORT="$IRCADB_DIR/ablation_report.json"

# Get patient number
PATIENT_NUM="5"
if [ -f /tmp/ircadb_patient_num ]; then
    PATIENT_NUM=$(cat /tmp/ircadb_patient_num)
fi

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/ablation_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
    
    # Try to export any markups from Slicer before checking files
    cat > /tmp/export_ablation_markups.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/IRCADb"
os.makedirs(output_dir, exist_ok=True)

measurements = []

# Export line markups (ruler measurements)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        measurements.append({
            "name": node.GetName(),
            "type": "line",
            "length_mm": round(length, 2),
            "p1": [round(x, 2) for x in p1],
            "p2": [round(x, 2) for x in p2]
        })
        print(f"  {node.GetName()}: {length:.2f} mm")

# Export fiducial markups (entry points)
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        measurements.append({
            "name": label or node.GetName(),
            "type": "fiducial",
            "position": [round(x, 2) for x in pos]
        })
        print(f"  Fiducial {label}: {pos}")

# Save measurements
if measurements:
    meas_path = os.path.join(output_dir, "lesion_measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": measurements, "exported_from_slicer": True}, f, indent=2)
    print(f"Exported {len(measurements)} measurements to {meas_path}")
else:
    print("No markups found in Slicer scene")

print("Export complete")
PYEOF

    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_ablation_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_ablation_markups" 2>/dev/null || true
fi

# Check for measurement file
MARKUP_EXISTS="false"
MARKUP_SIZE=0
MARKUP_MTIME=0
MARKUP_CREATED_AFTER_START="false"

POSSIBLE_MARKUP_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$IRCADB_DIR/measurements.mrk.json"
    "$IRCADB_DIR/measurement.mrk.json"
    "/home/ga/Documents/lesion_measurements.mrk.json"
)

for path in "${POSSIBLE_MARKUP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUP_EXISTS="true"
        MARKUP_SIZE=$(stat -c%s "$path" 2>/dev/null || echo "0")
        MARKUP_MTIME=$(stat -c%Y "$path" 2>/dev/null || echo "0")
        echo "Found measurement file: $path (${MARKUP_SIZE} bytes)"
        
        if [ "$MARKUP_MTIME" -gt "$TASK_START" ]; then
            MARKUP_CREATED_AFTER_START="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_CREATED_AFTER_START="false"
REPORT_CONTENT=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$IRCADB_DIR/report.json"
    "$IRCADB_DIR/ablation_assessment.json"
    "/home/ga/Documents/ablation_report.json"
    "/home/ga/ablation_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_SIZE=$(stat -c%s "$path" 2>/dev/null || echo "0")
        REPORT_MTIME=$(stat -c%Y "$path" 2>/dev/null || echo "0")
        echo "Found report file: $path (${REPORT_SIZE} bytes)"
        
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_AFTER_START="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Read report content for extraction
        REPORT_CONTENT=$(cat "$path" 2>/dev/null || echo "{}")
        break
    fi
done

# Extract key values from report if exists
REPORTED_CLASSIFICATION=""
REPORTED_MAX_DIM=""
REPORTED_HV_DIST=""
REPORTED_PV_DIST=""
REPORTED_CAP_DIST=""
REPORTED_SEGMENT=""
ENTRY_POINT_EXISTS="false"

if [ "$REPORT_EXISTS" = "true" ] && [ -f "$OUTPUT_REPORT" ]; then
    REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('suitability_classification', ''))" 2>/dev/null || echo "")
    REPORTED_MAX_DIM=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('max_dimension_mm', ''))" 2>/dev/null || echo "")
    REPORTED_HV_DIST=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('distance_to_hepatic_vein_mm', ''))" 2>/dev/null || echo "")
    REPORTED_PV_DIST=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('distance_to_portal_vein_mm', ''))" 2>/dev/null || echo "")
    REPORTED_CAP_DIST=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('distance_to_capsule_mm', ''))" 2>/dev/null || echo "")
    REPORTED_SEGMENT=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('liver_segment', ''))" 2>/dev/null || echo "")
    
    # Check for entry point
    ENTRY_CHECK=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); ep=d.get('proposed_entry_point'); print('true' if ep and isinstance(ep, list) and len(ep)==3 else 'false')" 2>/dev/null || echo "false")
    ENTRY_POINT_EXISTS="$ENTRY_CHECK"
    
    echo "Report values:"
    echo "  Classification: $REPORTED_CLASSIFICATION"
    echo "  Max dimension: $REPORTED_MAX_DIM mm"
    echo "  Hepatic vein distance: $REPORTED_HV_DIST mm"
    echo "  Portal vein distance: $REPORTED_PV_DIST mm"
    echo "  Capsule distance: $REPORTED_CAP_DIST mm"
    echo "  Liver segment: $REPORTED_SEGMENT"
    echo "  Entry point: $ENTRY_POINT_EXISTS"
fi

# Copy ground truth for verification
GT_JSON="$GROUND_TRUTH_DIR/ircadb_patient${PATIENT_NUM}_gt.json"
if [ -f "$GT_JSON" ]; then
    cp "$GT_JSON" /tmp/ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/ground_truth.json 2>/dev/null || true
    echo "Ground truth copied for verification"
fi

# Copy agent files for verification
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/agent_measurement.json 2>/dev/null || true
    chmod 644 /tmp/agent_measurement.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "patient_num": "$PATIENT_NUM",
    "markup_exists": $MARKUP_EXISTS,
    "markup_size": $MARKUP_SIZE,
    "markup_created_after_start": $MARKUP_CREATED_AFTER_START,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_created_after_start": $REPORT_CREATED_AFTER_START,
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "reported_max_dimension_mm": "$REPORTED_MAX_DIM",
    "reported_hv_distance_mm": "$REPORTED_HV_DIST",
    "reported_pv_distance_mm": "$REPORTED_PV_DIST",
    "reported_capsule_distance_mm": "$REPORTED_CAP_DIST",
    "reported_segment": "$REPORTED_SEGMENT",
    "entry_point_exists": $ENTRY_POINT_EXISTS,
    "ground_truth_path": "/tmp/ground_truth.json",
    "agent_report_path": "/tmp/agent_report.json",
    "agent_measurement_path": "/tmp/agent_measurement.json",
    "screenshot_path": "/tmp/ablation_final.png"
}
EOF

# Move to final location
rm -f /tmp/ablation_task_result.json 2>/dev/null || sudo rm -f /tmp/ablation_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/ablation_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/ablation_task_result.json
chmod 666 /tmp/ablation_task_result.json 2>/dev/null || sudo chmod 666 /tmp/ablation_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/ablation_task_result.json
echo ""
echo "=== Export Complete ==="