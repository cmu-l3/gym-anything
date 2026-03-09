#!/bin/bash
echo "=== Exporting Pericardial Effusion Result ==="

source /workspace/scripts/task_utils.sh

CARDIAC_DIR="/home/ga/Documents/SlicerData/Cardiac"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MEASUREMENT="$CARDIAC_DIR/pericardial_thickness.mrk.json"
OUTPUT_SEGMENTATION="$CARDIAC_DIR/pericardial_effusion_seg.nii.gz"
OUTPUT_REPORT="$CARDIAC_DIR/pericardial_report.json"

# Get task timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/pericardial_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer before closing
    cat > /tmp/export_pericardial_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/Cardiac"
os.makedirs(output_dir, exist_ok=True)

all_measurements = []

# Check for line/ruler markups
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
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "midpoint": [(a+b)/2 for a,b in zip(p1, p2)]
        }
        all_measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.1f} mm")
        
        # Save individual markup
        mrk_path = os.path.join(output_dir, "pericardial_thickness.mrk.json")
        slicer.util.saveNode(node, mrk_path)

# Check for segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for seg_node in seg_nodes:
    # Export segmentation as labelmap
    labelmapNode = slicer.mrmlScene.AddNewNodeByClass("vtkMRMLLabelMapVolumeNode")
    slicer.modules.segmentations.logic().ExportAllSegmentsToLabelmapNode(
        seg_node, labelmapNode)
    
    seg_path = os.path.join(output_dir, "pericardial_effusion_seg.nii.gz")
    slicer.util.saveNode(labelmapNode, seg_path)
    print(f"  Segmentation exported to {seg_path}")
    
    # Clean up
    slicer.mrmlScene.RemoveNode(labelmapNode)

# Save all measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "agent_measurements.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Exported {len(all_measurements)} measurements")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_pericardial_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_pericardial_meas" 2>/dev/null || true
fi

# Check for measurement file
MEASUREMENT_EXISTS="false"
MEASURED_THICKNESS=""
MEASUREMENT_MTIME="0"

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$CARDIAC_DIR/pericardial_thickness.mrk.json"
    "$CARDIAC_DIR/agent_measurements.json"
    "$CARDIAC_DIR/thickness.mrk.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENT_EXISTS="true"
        MEASUREMENT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found measurement at: $path"
        
        # Try to extract thickness
        MEASURED_THICKNESS=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
# Try different formats
if 'measurements' in data:
    for m in data['measurements']:
        if m.get('type') == 'line' and m.get('length_mm', 0) > 0:
            print(f\"{m['length_mm']:.2f}\")
            break
elif 'markups' in data:
    for m in data.get('markups', []):
        if 'measurements' in m:
            for meas in m['measurements']:
                if 'value' in meas:
                    print(f\"{meas['value']:.2f}\")
                    break
" 2>/dev/null || echo "")
        
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        break
    fi
done

# Check for segmentation file
SEGMENTATION_EXISTS="false"
SEGMENTATION_SIZE="0"
SEGMENTATION_MTIME="0"

POSSIBLE_SEG_PATHS=(
    "$OUTPUT_SEGMENTATION"
    "$CARDIAC_DIR/pericardial_effusion_seg.nii.gz"
    "$CARDIAC_DIR/Segmentation.nii.gz"
    "$CARDIAC_DIR/effusion_seg.nii.gz"
)

for path in "${POSSIBLE_SEG_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SEGMENTATION_EXISTS="true"
        SEGMENTATION_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SEGMENTATION_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found segmentation at: $path"
        
        if [ "$path" != "$OUTPUT_SEGMENTATION" ]; then
            cp "$path" "$OUTPUT_SEGMENTATION" 2>/dev/null || true
        fi
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORTED_THICKNESS=""
REPORTED_VOLUME=""
REPORTED_SEVERITY=""
REPORTED_LOCATION=""
REPORTED_DISTRIBUTION=""
REPORT_MTIME="0"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$CARDIAC_DIR/pericardial_report.json"
    "$CARDIAC_DIR/report.json"
    "/home/ga/pericardial_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found report at: $path"
        
        REPORTED_THICKNESS=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('max_thickness_mm', d.get('thickness_mm', '')))" 2>/dev/null || echo "")
        REPORTED_VOLUME=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('effusion_volume_ml', d.get('volume_ml', '')))" 2>/dev/null || echo "")
        REPORTED_SEVERITY=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('severity_classification', d.get('severity', '')))" 2>/dev/null || echo "")
        REPORTED_LOCATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('max_thickness_location', d.get('location', '')))" 2>/dev/null || echo "")
        REPORTED_DISTRIBUTION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('distribution_pattern', d.get('distribution', '')))" 2>/dev/null || echo "")
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        break
    fi
done

# Check if files were created during task
MEASUREMENT_CREATED="false"
SEGMENTATION_CREATED="false"
REPORT_CREATED="false"

if [ "$MEASUREMENT_EXISTS" = "true" ] && [ "$MEASUREMENT_MTIME" -gt "$TASK_START" ]; then
    MEASUREMENT_CREATED="true"
fi
if [ "$SEGMENTATION_EXISTS" = "true" ] && [ "$SEGMENTATION_MTIME" -gt "$TASK_START" ]; then
    SEGMENTATION_CREATED="true"
fi
if [ "$REPORT_EXISTS" = "true" ] && [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_CREATED="true"
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Copy ground truth for verification
echo "Preparing files for verification..."
cp "$GROUND_TRUTH_DIR/pericardial_effusion_gt.json" /tmp/pericardial_gt.json 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/pericardial_effusion_gt_seg.nii.gz" /tmp/pericardial_gt_seg.nii.gz 2>/dev/null || true
chmod 644 /tmp/pericardial_gt.json /tmp/pericardial_gt_seg.nii.gz 2>/dev/null || true

if [ -f "$OUTPUT_SEGMENTATION" ]; then
    cp "$OUTPUT_SEGMENTATION" /tmp/agent_pericardial_seg.nii.gz 2>/dev/null || true
    chmod 644 /tmp/agent_pericardial_seg.nii.gz 2>/dev/null || true
fi

if [ -f "$OUTPUT_MEASUREMENT" ]; then
    cp "$OUTPUT_MEASUREMENT" /tmp/agent_pericardial_meas.json 2>/dev/null || true
    chmod 644 /tmp/agent_pericardial_meas.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_pericardial_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_pericardial_report.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "measurement_exists": $MEASUREMENT_EXISTS,
    "measurement_created_during_task": $MEASUREMENT_CREATED,
    "measured_thickness_mm": "$MEASURED_THICKNESS",
    "segmentation_exists": $SEGMENTATION_EXISTS,
    "segmentation_created_during_task": $SEGMENTATION_CREATED,
    "segmentation_size_bytes": $SEGMENTATION_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED,
    "reported_thickness_mm": "$REPORTED_THICKNESS",
    "reported_volume_ml": "$REPORTED_VOLUME",
    "reported_severity": "$REPORTED_SEVERITY",
    "reported_location": "$REPORTED_LOCATION",
    "reported_distribution": "$REPORTED_DISTRIBUTION",
    "screenshot_exists": $([ -f "/tmp/pericardial_final.png" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/pericardial_task_result.json 2>/dev/null || sudo rm -f /tmp/pericardial_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/pericardial_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/pericardial_task_result.json
chmod 666 /tmp/pericardial_task_result.json 2>/dev/null || sudo chmod 666 /tmp/pericardial_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/pericardial_task_result.json
echo ""
echo "=== Export Complete ==="