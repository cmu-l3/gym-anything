#!/bin/bash
echo "=== Exporting Bone Density Screening Results ==="

source /workspace/scripts/task_utils.sh

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_DIR="/tmp/task_output"

mkdir -p "$OUTPUT_DIR"

# Get patient ID
PATIENT_ID=$(cat /tmp/bone_density_patient_id.txt 2>/dev/null || echo "LIDC-IDRI-0001")

# Get task timing for anti-gaming
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_state.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Check for agent's report file
REPORT_FILE="$LIDC_DIR/bone_density_report.json"
REPORT_EXISTS="false"
REPORT_VALID="false"
AGENT_HU=""
AGENT_CLASSIFICATION=""
AGENT_LEVEL=""
AGENT_ROI_AREA=""

# Search for report in multiple locations
POSSIBLE_REPORTS=(
    "$LIDC_DIR/bone_density_report.json"
    "$LIDC_DIR/report.json"
    "/home/ga/Documents/bone_density_report.json"
    "/home/ga/bone_density_report.json"
)

for rpath in "${POSSIBLE_REPORTS[@]}"; do
    if [ -f "$rpath" ]; then
        REPORT_FILE="$rpath"
        REPORT_EXISTS="true"
        
        # Check if created during task (anti-gaming)
        FILE_MTIME=$(stat -c %Y "$rpath" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        else
            REPORT_CREATED_DURING_TASK="false"
        fi
        
        # Parse report contents
        AGENT_HU=$(python3 -c "
import json
try:
    with open('$rpath') as f:
        data = json.load(f)
    val = data.get('mean_hu', data.get('hu', data.get('HU', '')))
    print(val if val != '' else '')
except Exception as e:
    print('')
" 2>/dev/null || echo "")

        AGENT_CLASSIFICATION=$(python3 -c "
import json
try:
    with open('$rpath') as f:
        data = json.load(f)
    print(data.get('classification', data.get('Classification', '')))
except:
    print('')
" 2>/dev/null || echo "")

        AGENT_LEVEL=$(python3 -c "
import json
try:
    with open('$rpath') as f:
        data = json.load(f)
    print(data.get('vertebral_level', data.get('level', '')))
except:
    print('')
" 2>/dev/null || echo "")

        AGENT_ROI_AREA=$(python3 -c "
import json
try:
    with open('$rpath') as f:
        data = json.load(f)
    val = data.get('roi_area_mm2', data.get('area', data.get('roi_area', '')))
    print(val if val != '' else '')
except:
    print('')
" 2>/dev/null || echo "")

        if [ -n "$AGENT_HU" ] && [ -n "$AGENT_CLASSIFICATION" ]; then
            REPORT_VALID="true"
        fi
        
        echo "Found report at: $rpath"
        break
    fi
done

# Check for ROI file
ROI_FILE=""
ROI_EXISTS="false"
ROI_CREATED_DURING_TASK="false"

POSSIBLE_ROIS=(
    "$LIDC_DIR/bone_density_roi.seg.nrrd"
    "$LIDC_DIR/bone_density_roi.mrk.json"
    "$LIDC_DIR/roi.seg.nrrd"
    "$LIDC_DIR/Segmentation.seg.nrrd"
)

for roipath in "${POSSIBLE_ROIS[@]}"; do
    if [ -f "$roipath" ]; then
        ROI_FILE="$roipath"
        ROI_EXISTS="true"
        
        FILE_MTIME=$(stat -c %Y "$roipath" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            ROI_CREATED_DURING_TASK="true"
        fi
        
        echo "Found ROI at: $roipath"
        break
    fi
done

# Also check for any segmentation file created during task
if [ "$ROI_EXISTS" = "false" ]; then
    for segfile in "$LIDC_DIR"/*.seg.nrrd "$LIDC_DIR"/*.nrrd; do
        if [ -f "$segfile" ]; then
            FILE_MTIME=$(stat -c %Y "$segfile" 2>/dev/null || echo "0")
            if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
                ROI_FILE="$segfile"
                ROI_EXISTS="true"
                ROI_CREATED_DURING_TASK="true"
                echo "Found segmentation created during task: $segfile"
                break
            fi
        fi
    done
fi

# Check for screenshots created during task
SCREENSHOT_COUNT=0
SCREENSHOT_PATH=""
for ssdir in "$LIDC_DIR" "/home/ga/Documents/SlicerData/Screenshots" "/home/ga/Documents"; do
    for ssfile in "$ssdir"/*.png; do
        if [ -f "$ssfile" ]; then
            FILE_MTIME=$(stat -c %Y "$ssfile" 2>/dev/null || echo "0")
            if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
                SCREENSHOT_COUNT=$((SCREENSHOT_COUNT + 1))
                if [ -z "$SCREENSHOT_PATH" ]; then
                    SCREENSHOT_PATH="$ssfile"
                fi
            fi
        fi
    done
done

SCREENSHOT_EXISTS="false"
if [ "$SCREENSHOT_COUNT" -gt 0 ]; then
    SCREENSHOT_EXISTS="true"
fi

# Copy ground truth for verifier
GT_FILE="$GROUND_TRUTH_DIR/${PATIENT_ID}_bone_density_gt.json"
if [ -f "$GT_FILE" ]; then
    cp "$GT_FILE" /tmp/bone_density_gt.json 2>/dev/null || true
    chmod 644 /tmp/bone_density_gt.json 2>/dev/null || true
fi

# Copy agent files to output
cp "$REPORT_FILE" "$OUTPUT_DIR/agent_report.json" 2>/dev/null || true
cp "$ROI_FILE" "$OUTPUT_DIR/agent_roi" 2>/dev/null || true
cp "$SCREENSHOT_PATH" "$OUTPUT_DIR/agent_screenshot.png" 2>/dev/null || true
cp /tmp/task_final_state.png "$OUTPUT_DIR/final_screenshot.png" 2>/dev/null || true

# Build result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_id": "$PATIENT_ID",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_created_during_task": ${REPORT_CREATED_DURING_TASK:-false},
    "agent_mean_hu": "$AGENT_HU",
    "agent_classification": "$AGENT_CLASSIFICATION",
    "agent_vertebral_level": "$AGENT_LEVEL",
    "agent_roi_area_mm2": "$AGENT_ROI_AREA",
    "roi_file_exists": $ROI_EXISTS,
    "roi_created_during_task": $ROI_CREATED_DURING_TASK,
    "roi_file_path": "$ROI_FILE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_count": $SCREENSHOT_COUNT,
    "ground_truth_available": $([ -f /tmp/bone_density_gt.json ] && echo "true" || echo "false")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="