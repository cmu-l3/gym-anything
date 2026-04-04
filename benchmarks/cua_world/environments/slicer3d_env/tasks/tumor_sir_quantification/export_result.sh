#!/bin/bash
echo "=== Exporting Tumor SIR Quantification Result ==="

source /workspace/scripts/task_utils.sh

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_ROIS="$BRATS_DIR/sir_rois.mrk.json"
OUTPUT_REPORT="$BRATS_DIR/sir_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/sir_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export ROI data from Slicer before closing
    cat > /tmp/export_sir_data.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

rois_data = {"rois": [], "measurements": []}

# Check for ROI nodes (vtkMRMLMarkupsROINode)
roi_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsROINode")
print(f"Found {len(roi_nodes)} ROI node(s)")

for node in roi_nodes:
    center = [0.0, 0.0, 0.0]
    node.GetCenter(center)
    radius = node.GetRadiusXYZ()
    
    roi_info = {
        "name": node.GetName(),
        "type": "roi",
        "center_ras": center,
        "radius_xyz": list(radius),
    }
    rois_data["rois"].append(roi_info)
    print(f"  ROI '{node.GetName()}': center={center}, radius={radius}")

# Check for fiducial markups as alternative
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        rois_data["rois"].append({
            "name": label,
            "type": "fiducial",
            "center_ras": pos,
        })
        print(f"  Fiducial '{label}': position={pos}")

# Check for line markups (might be used for measurements)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line node(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        rois_data["measurements"].append({
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
        })

# Save ROI data
if rois_data["rois"] or rois_data["measurements"]:
    rois_path = os.path.join(output_dir, "sir_rois.mrk.json")
    with open(rois_path, "w") as f:
        json.dump(rois_data, f, indent=2)
    print(f"Exported ROI data to {rois_path}")
    
    # Also save individual markup nodes
    for node in roi_nodes:
        mrk_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        try:
            slicer.util.saveNode(node, mrk_path)
        except:
            pass
else:
    print("No ROI data found in scene")

print("Export complete")
PYEOF
    
    # Run the export script in Slicer (background, with timeout)
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_sir_data.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_sir_data" 2>/dev/null || true
fi

# Check if ROI file exists
ROI_EXISTS="false"
ROI_PATH=""
ROI_CREATED_DURING_TASK="false"

POSSIBLE_ROI_PATHS=(
    "$OUTPUT_ROIS"
    "$BRATS_DIR/sir_rois.mrk.json"
    "$BRATS_DIR/TumorROI.mrk.json"
    "$BRATS_DIR/ROI.mrk.json"
    "/home/ga/Documents/sir_rois.mrk.json"
)

for path in "${POSSIBLE_ROI_PATHS[@]}"; do
    if [ -f "$path" ]; then
        ROI_EXISTS="true"
        ROI_PATH="$path"
        echo "Found ROI file at: $path"
        
        # Check if file was created during task
        ROI_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$ROI_MTIME" -gt "$TASK_START" ]; then
            ROI_CREATED_DURING_TASK="true"
        fi
        
        if [ "$path" != "$OUTPUT_ROIS" ]; then
            cp "$path" "$OUTPUT_ROIS" 2>/dev/null || true
        fi
        break
    fi
done

# Check if report file exists
REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_CREATED_DURING_TASK="false"
REPORT_DATA="{}"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/sir_report.json"
    "$BRATS_DIR/report.json"
    "/home/ga/Documents/sir_report.json"
    "/home/ga/sir_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report file at: $path"
        
        # Check if file was created during task
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
        
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Read report data
        REPORT_DATA=$(cat "$path" 2>/dev/null || echo "{}")
        break
    fi
done

# Extract SIR values from report if available
SIR_T1=""
SIR_T1CE=""
SIR_T2=""
SIR_FLAIR=""

if [ "$REPORT_EXISTS" = "true" ]; then
    SIR_T1=$(python3 -c "import json; d=json.load(open('$REPORT_PATH')); print(d.get('sir_values', {}).get('t1', ''))" 2>/dev/null || echo "")
    SIR_T1CE=$(python3 -c "import json; d=json.load(open('$REPORT_PATH')); print(d.get('sir_values', {}).get('t1ce', d.get('sir_values', {}).get('t1_contrast', '')))" 2>/dev/null || echo "")
    SIR_T2=$(python3 -c "import json; d=json.load(open('$REPORT_PATH')); print(d.get('sir_values', {}).get('t2', ''))" 2>/dev/null || echo "")
    SIR_FLAIR=$(python3 -c "import json; d=json.load(open('$REPORT_PATH')); print(d.get('sir_values', {}).get('flair', ''))" 2>/dev/null || echo "")
    
    echo "Extracted SIR values: T1=$SIR_T1, T1ce=$SIR_T1CE, T2=$SIR_T2, FLAIR=$SIR_FLAIR"
fi

# Copy ground truth for verification
echo "Preparing ground truth for verification..."
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_seg.nii.gz" /tmp/ground_truth_seg.nii.gz 2>/dev/null || true
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_stats.json" /tmp/ground_truth_stats.json 2>/dev/null || true
chmod 644 /tmp/ground_truth_seg.nii.gz /tmp/ground_truth_stats.json 2>/dev/null || true

# Copy ROI and report files for verification
if [ -f "$OUTPUT_ROIS" ]; then
    cp "$OUTPUT_ROIS" /tmp/agent_rois.json 2>/dev/null || true
    chmod 644 /tmp/agent_rois.json 2>/dev/null || true
fi

if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_report.json 2>/dev/null || true
fi

# Count screenshots created during task
SCREENSHOT_COUNT=$(find "$BRATS_DIR" /home/ga/Documents -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "roi_file_exists": $ROI_EXISTS,
    "roi_file_path": "$ROI_PATH",
    "roi_created_during_task": $ROI_CREATED_DURING_TASK,
    "report_file_exists": $REPORT_EXISTS,
    "report_file_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "sir_values": {
        "t1": "$SIR_T1",
        "t1ce": "$SIR_T1CE",
        "t2": "$SIR_T2",
        "flair": "$SIR_FLAIR"
    },
    "screenshot_count": $SCREENSHOT_COUNT,
    "screenshot_exists": $([ -f "/tmp/sir_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/ground_truth_seg.nii.gz" ] && echo "true" || echo "false"),
    "sample_id": "$SAMPLE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/sir_task_result.json 2>/dev/null || sudo rm -f /tmp/sir_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/sir_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/sir_task_result.json
chmod 666 /tmp/sir_task_result.json 2>/dev/null || sudo chmod 666 /tmp/sir_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/sir_task_result.json
echo ""
echo "=== Export Complete ==="