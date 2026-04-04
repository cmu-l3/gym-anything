#!/bin/bash
echo "=== Exporting Liver Steatosis Assessment Result ==="

source /workspace/scripts/task_utils.sh

STEATOSIS_DIR="/home/ga/Documents/SlicerData/Steatosis"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get case ID
if [ -f /tmp/steatosis_case_id.txt ]; then
    CASE_ID=$(cat /tmp/steatosis_case_id.txt)
else
    CASE_ID="steatosis_case"
fi

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/steatosis_final.png ga
sleep 1

# Check Slicer state
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any markups from Slicer
    cat > /tmp/export_steatosis_markups.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/Steatosis"
os.makedirs(output_dir, exist_ok=True)

# Find all fiducial nodes
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    name = node.GetName().lower()
    n_points = node.GetNumberOfControlPoints()
    
    if n_points > 0:
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, pos)
        
        # Save based on name
        if "liver" in name:
            path = os.path.join(output_dir, "liver_roi.mrk.json")
            slicer.util.saveNode(node, path)
            print(f"Saved liver ROI to {path}")
        elif "spleen" in name:
            path = os.path.join(output_dir, "spleen_roi.mrk.json")
            slicer.util.saveNode(node, path)
            print(f"Saved spleen ROI to {path}")
        else:
            # Save with original name
            path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
            slicer.util.saveNode(node, path)
            print(f"Saved {node.GetName()} to {path}")

# Also check for any ROI nodes
roi_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsROINode")
print(f"Found {len(roi_nodes)} ROI node(s)")

for node in roi_nodes:
    name = node.GetName().lower()
    if "liver" in name:
        path = os.path.join(output_dir, "liver_roi.mrk.json")
        slicer.util.saveNode(node, path)
    elif "spleen" in name:
        path = os.path.join(output_dir, "spleen_roi.mrk.json")
        slicer.util.saveNode(node, path)

print("Markup export complete")
PYEOF
    
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_steatosis_markups.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_steatosis_markups" 2>/dev/null || true
fi

# Check for liver ROI
LIVER_ROI_EXISTS="false"
LIVER_ROI_PATH=""

POSSIBLE_LIVER_PATHS=(
    "$STEATOSIS_DIR/liver_roi.mrk.json"
    "$STEATOSIS_DIR/Liver.mrk.json"
    "$STEATOSIS_DIR/liver.mrk.json"
    "$STEATOSIS_DIR/LiverROI.mrk.json"
)

for path in "${POSSIBLE_LIVER_PATHS[@]}"; do
    if [ -f "$path" ]; then
        LIVER_ROI_EXISTS="true"
        LIVER_ROI_PATH="$path"
        echo "Found liver ROI at: $path"
        if [ "$path" != "$STEATOSIS_DIR/liver_roi.mrk.json" ]; then
            cp "$path" "$STEATOSIS_DIR/liver_roi.mrk.json" 2>/dev/null || true
        fi
        break
    fi
done

# Check for spleen ROI
SPLEEN_ROI_EXISTS="false"
SPLEEN_ROI_PATH=""

POSSIBLE_SPLEEN_PATHS=(
    "$STEATOSIS_DIR/spleen_roi.mrk.json"
    "$STEATOSIS_DIR/Spleen.mrk.json"
    "$STEATOSIS_DIR/spleen.mrk.json"
    "$STEATOSIS_DIR/SpleenROI.mrk.json"
)

for path in "${POSSIBLE_SPLEEN_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SPLEEN_ROI_EXISTS="true"
        SPLEEN_ROI_PATH="$path"
        echo "Found spleen ROI at: $path"
        if [ "$path" != "$STEATOSIS_DIR/spleen_roi.mrk.json" ]; then
            cp "$path" "$STEATOSIS_DIR/spleen_roi.mrk.json" 2>/dev/null || true
        fi
        break
    fi
done

# Check for report file
REPORT_EXISTS="false"
REPORT_PATH=""
LIVER_HU_REPORTED=""
SPLEEN_HU_REPORTED=""
LS_RATIO_REPORTED=""
CLASSIFICATION_REPORTED=""

POSSIBLE_REPORT_PATHS=(
    "$STEATOSIS_DIR/steatosis_report.json"
    "$STEATOSIS_DIR/report.json"
    "$STEATOSIS_DIR/steatosis.json"
    "/home/ga/Documents/steatosis_report.json"
    "/home/ga/steatosis_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        if [ "$path" != "$STEATOSIS_DIR/steatosis_report.json" ]; then
            cp "$path" "$STEATOSIS_DIR/steatosis_report.json" 2>/dev/null || true
        fi
        
        # Extract values from report
        LIVER_HU_REPORTED=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    v = d.get('liver_hu', d.get('liver_mean_hu', d.get('liverHU', '')))
    print(v if v != '' else 'null')
except:
    print('null')
" 2>/dev/null || echo "null")
        
        SPLEEN_HU_REPORTED=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    v = d.get('spleen_hu', d.get('spleen_mean_hu', d.get('spleenHU', '')))
    print(v if v != '' else 'null')
except:
    print('null')
" 2>/dev/null || echo "null")
        
        LS_RATIO_REPORTED=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    v = d.get('ls_ratio', d.get('liver_spleen_ratio', d.get('LSRatio', d.get('ratio', ''))))
    print(v if v != '' else 'null')
except:
    print('null')
" 2>/dev/null || echo "null")
        
        CLASSIFICATION_REPORTED=$(python3 -c "
import json
try:
    with open('$path') as f:
        d = json.load(f)
    v = d.get('classification', d.get('steatosis_grade', d.get('grade', d.get('diagnosis', ''))))
    print(v if v != '' else 'null')
except:
    print('null')
" 2>/dev/null || echo "null")
        
        break
    fi
done

echo "Report values extracted:"
echo "  Liver HU: $LIVER_HU_REPORTED"
echo "  Spleen HU: $SPLEEN_HU_REPORTED"
echo "  L/S Ratio: $LS_RATIO_REPORTED"
echo "  Classification: $CLASSIFICATION_REPORTED"

# Check file timestamps to detect pre-existing files
LIVER_ROI_MODIFIED_DURING_TASK="false"
SPLEEN_ROI_MODIFIED_DURING_TASK="false"
REPORT_MODIFIED_DURING_TASK="false"

if [ "$LIVER_ROI_EXISTS" = "true" ] && [ -f "$STEATOSIS_DIR/liver_roi.mrk.json" ]; then
    LIVER_ROI_MTIME=$(stat -c %Y "$STEATOSIS_DIR/liver_roi.mrk.json" 2>/dev/null || echo "0")
    if [ "$LIVER_ROI_MTIME" -gt "$TASK_START" ]; then
        LIVER_ROI_MODIFIED_DURING_TASK="true"
    fi
fi

if [ "$SPLEEN_ROI_EXISTS" = "true" ] && [ -f "$STEATOSIS_DIR/spleen_roi.mrk.json" ]; then
    SPLEEN_ROI_MTIME=$(stat -c %Y "$STEATOSIS_DIR/spleen_roi.mrk.json" 2>/dev/null || echo "0")
    if [ "$SPLEEN_ROI_MTIME" -gt "$TASK_START" ]; then
        SPLEEN_ROI_MODIFIED_DURING_TASK="true"
    fi
fi

if [ "$REPORT_EXISTS" = "true" ] && [ -f "$STEATOSIS_DIR/steatosis_report.json" ]; then
    REPORT_MTIME=$(stat -c %Y "$STEATOSIS_DIR/steatosis_report.json" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED_DURING_TASK="true"
    fi
fi

# Check for final screenshot
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/steatosis_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/steatosis_gt.json" /tmp/steatosis_gt.json 2>/dev/null || true
chmod 644 /tmp/steatosis_gt.json 2>/dev/null || true

# Copy ROI files for verifier
cp "$STEATOSIS_DIR/liver_roi.mrk.json" /tmp/liver_roi.mrk.json 2>/dev/null || true
cp "$STEATOSIS_DIR/spleen_roi.mrk.json" /tmp/spleen_roi.mrk.json 2>/dev/null || true
cp "$STEATOSIS_DIR/steatosis_report.json" /tmp/steatosis_report.json 2>/dev/null || true
chmod 644 /tmp/liver_roi.mrk.json /tmp/spleen_roi.mrk.json /tmp/steatosis_report.json 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "liver_roi_exists": $LIVER_ROI_EXISTS,
    "liver_roi_modified_during_task": $LIVER_ROI_MODIFIED_DURING_TASK,
    "spleen_roi_exists": $SPLEEN_ROI_EXISTS,
    "spleen_roi_modified_during_task": $SPLEEN_ROI_MODIFIED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_modified_during_task": $REPORT_MODIFIED_DURING_TASK,
    "liver_hu_reported": $LIVER_HU_REPORTED,
    "spleen_hu_reported": $SPLEEN_HU_REPORTED,
    "ls_ratio_reported": $LS_RATIO_REPORTED,
    "classification_reported": "$CLASSIFICATION_REPORTED",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "case_id": "$CASE_ID",
    "steatosis_dir": "$STEATOSIS_DIR",
    "ground_truth_dir": "$GROUND_TRUTH_DIR",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/steatosis_task_result.json 2>/dev/null || sudo rm -f /tmp/steatosis_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/steatosis_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/steatosis_task_result.json
chmod 666 /tmp/steatosis_task_result.json 2>/dev/null || sudo chmod 666 /tmp/steatosis_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/steatosis_task_result.json
echo ""
echo "=== Export Complete ==="