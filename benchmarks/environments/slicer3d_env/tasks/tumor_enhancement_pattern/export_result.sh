#!/bin/bash
echo "=== Exporting Tumor Enhancement Pattern Results ==="

source /workspace/scripts/task_utils.sh

# Get sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_REPORT="$BRATS_DIR/enhancement_report.json"
OUTPUT_ROI="$BRATS_DIR/enhancement_rois.mrk.json"

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TASK_DURATION=$((TASK_END - TASK_START))

echo "Task duration: ${TASK_DURATION} seconds"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/enhancement_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Check for agent's report file
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_PATH=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$BRATS_DIR/enhancement_report.json"
    "$BRATS_DIR/report.json"
    "/home/ga/Documents/enhancement_report.json"
    "/home/ga/enhancement_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Copy to expected location if needed
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Validate JSON structure
        if python3 -c "
import json
with open('$path', 'r') as f:
    data = json.load(f)
    required = ['enhancement_ratio', 'classification']
    if any(k in str(data).lower() for k in ['enhancement', 'ratio']):
        exit(0)
    exit(1)
" 2>/dev/null; then
            REPORT_VALID="true"
        fi
        break
    fi
done

# Check for ROI markups file
ROI_EXISTS="false"
ROI_PATH=""

POSSIBLE_ROI_PATHS=(
    "$OUTPUT_ROI"
    "$BRATS_DIR/enhancement_rois.mrk.json"
    "$BRATS_DIR/rois.mrk.json"
    "$BRATS_DIR/markups.mrk.json"
)

for path in "${POSSIBLE_ROI_PATHS[@]}"; do
    if [ -f "$path" ]; then
        ROI_EXISTS="true"
        ROI_PATH="$path"
        echo "Found ROI file at: $path"
        if [ "$path" != "$OUTPUT_ROI" ]; then
            cp "$path" "$OUTPUT_ROI" 2>/dev/null || true
        fi
        break
    fi
done

# Try to extract measurements from Slicer if running
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Attempting to extract markups from Slicer..."
    cat > /tmp/export_enhancement_data.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Get all markup nodes
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")

all_markups = []

for node in fiducial_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        all_markups.append({
            "name": node.GetNthControlPointLabel(i),
            "type": "fiducial",
            "position": pos,
            "node_name": node.GetName()
        })

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        all_markups.append({
            "name": node.GetName(),
            "type": "line",
            "p1": p1,
            "p2": p2
        })

if all_markups:
    roi_path = os.path.join(output_dir, "enhancement_rois.mrk.json")
    with open(roi_path, "w") as f:
        json.dump({"markups": all_markups}, f, indent=2)
    print(f"Exported {len(all_markups)} markups to {roi_path}")
else:
    print("No markups found in scene")
PYEOF

    # Run extraction (with timeout)
    timeout 15 sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_enhancement_data.py --no-main-window > /tmp/slicer_export.log 2>&1 || true
    sleep 2
fi

# Extract values from report if it exists
AGENT_ER=""
AGENT_RE=""
AGENT_CLASS=""
AGENT_PATTERN=""
AGENT_T1_TUMOR=""
AGENT_T1CE_TUMOR=""

if [ -f "$OUTPUT_REPORT" ]; then
    AGENT_ER=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('enhancement_ratio', ''))" 2>/dev/null || echo "")
    AGENT_RE=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('relative_enhancement_percent', d.get('relative_enhancement', '')))" 2>/dev/null || echo "")
    AGENT_CLASS=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('classification', ''))" 2>/dev/null || echo "")
    AGENT_PATTERN=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('pattern', ''))" 2>/dev/null || echo "")
    AGENT_T1_TUMOR=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('t1_tumor_mean', ''))" 2>/dev/null || echo "")
    AGENT_T1CE_TUMOR=$(python3 -c "import json; d=json.load(open('$OUTPUT_REPORT')); print(d.get('t1ce_tumor_mean', ''))" 2>/dev/null || echo "")
fi

# Check if files were created during task
REPORT_CREATED_DURING_TASK="false"
ROI_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$OUTPUT_ROI" ]; then
    ROI_MTIME=$(stat -c %Y "$OUTPUT_ROI" 2>/dev/null || echo "0")
    if [ "$ROI_MTIME" -gt "$TASK_START" ]; then
        ROI_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_enhancement_gt.json" /tmp/enhancement_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/enhancement_ground_truth.json 2>/dev/null || true

# Copy agent report for verification
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_enhancement_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_enhancement_report.json 2>/dev/null || true
fi

# Copy ROI file for verification
if [ -f "$OUTPUT_ROI" ]; then
    cp "$OUTPUT_ROI" /tmp/agent_enhancement_rois.json 2>/dev/null || true
    chmod 644 /tmp/agent_enhancement_rois.json 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sample_id": "$SAMPLE_ID",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $TASK_DURATION,
    "slicer_was_running": $SLICER_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_path": "$REPORT_PATH",
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "roi_file_exists": $ROI_EXISTS,
    "roi_path": "$ROI_PATH",
    "roi_created_during_task": $ROI_CREATED_DURING_TASK,
    "agent_values": {
        "enhancement_ratio": "$AGENT_ER",
        "relative_enhancement": "$AGENT_RE",
        "classification": "$AGENT_CLASS",
        "pattern": "$AGENT_PATTERN",
        "t1_tumor_mean": "$AGENT_T1_TUMOR",
        "t1ce_tumor_mean": "$AGENT_T1CE_TUMOR"
    },
    "screenshot_exists": $([ -f "/tmp/enhancement_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/enhancement_ground_truth.json" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/enhancement_task_result.json 2>/dev/null || sudo rm -f /tmp/enhancement_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/enhancement_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/enhancement_task_result.json
chmod 666 /tmp/enhancement_task_result.json 2>/dev/null || sudo chmod 666 /tmp/enhancement_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/enhancement_task_result.json
echo ""
echo "=== Export Complete ==="