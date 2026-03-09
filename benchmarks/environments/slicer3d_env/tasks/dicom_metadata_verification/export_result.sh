#!/bin/bash
echo "=== Exporting DICOM Metadata Verification Result ==="

source /workspace/scripts/task_utils.sh

# Get patient ID
if [ -f /tmp/dicom_patient_id ]; then
    PATIENT_ID=$(cat /tmp/dicom_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_REPORT="$LIDC_DIR/dicom_qa_report.json"
OUTPUT_SCREENSHOT="$LIDC_DIR/metadata_verification_screenshot.png"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/dicom_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Check if data was loaded into Slicer
DATA_LOADED="false"
VOLUME_COUNT=0

if [ "$SLICER_RUNNING" = "true" ]; then
    # Query Slicer for loaded volumes
    VOLUME_COUNT=$(sudo -u ga DISPLAY=:1 /opt/Slicer/bin/PythonSlicer -c "
import slicer
nodes = slicer.mrmlScene.GetNodesByClass('vtkMRMLScalarVolumeNode')
print(nodes.GetNumberOfItems())
" 2>/dev/null || echo "0")
    
    if [ "$VOLUME_COUNT" -gt 0 ]; then
        DATA_LOADED="true"
        echo "Found $VOLUME_COUNT volume(s) loaded in Slicer"
    fi
fi

# Check for agent's QA report
REPORT_EXISTS="false"
REPORT_VALID_JSON="false"
REPORT_CREATED_DURING_TASK="false"

# Check multiple possible paths
POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/qa_report.json"
    "$LIDC_DIR/report.json"
    "/home/ga/Documents/dicom_qa_report.json"
    "/home/ga/dicom_qa_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found QA report at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Check if valid JSON
        if python3 -c "import json; json.load(open('$path'))" 2>/dev/null; then
            REPORT_VALID_JSON="true"
        fi
        
        # Check if created during task
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
        
        break
    fi
done

# Check for agent's screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0
SCREENSHOT_CREATED_DURING_TASK="false"

POSSIBLE_SCREENSHOT_PATHS=(
    "$OUTPUT_SCREENSHOT"
    "$LIDC_DIR/screenshot.png"
    "$LIDC_DIR/verification_screenshot.png"
    "/home/ga/Documents/metadata_verification_screenshot.png"
)

for path in "${POSSIBLE_SCREENSHOT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SCREENSHOT_EXISTS="true"
        SCREENSHOT_SIZE_KB=$(( $(stat -c %s "$path" 2>/dev/null || echo "0") / 1024 ))
        echo "Found screenshot at: $path (${SCREENSHOT_SIZE_KB}KB)"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_SCREENSHOT" ]; then
            cp "$path" "$OUTPUT_SCREENSHOT" 2>/dev/null || true
        fi
        
        # Check if created during task
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            SCREENSHOT_CREATED_DURING_TASK="true"
        fi
        
        break
    fi
done

# Extract agent's reported values from the QA report
AGENT_PATIENT_ID=""
AGENT_MODALITY=""
AGENT_SLICE_THICKNESS=""
AGENT_PIXEL_SPACING=""
AGENT_ROWS=""
AGENT_COLUMNS=""
AGENT_SLICES=""
AGENT_MANUFACTURER=""
AGENT_STUDY_DATE=""

if [ "$REPORT_VALID_JSON" = "true" ] && [ -f "$OUTPUT_REPORT" ]; then
    echo "Extracting agent's reported values..."
    python3 << PYEOF
import json
import os

report_path = "$OUTPUT_REPORT"

with open(report_path) as f:
    data = json.load(f)

# Handle both flat and nested structures
qa = data.get('qa_report', data)
acq = qa.get('acquisition_parameters', qa)
equip = qa.get('equipment', qa)

# Write values to temp files for shell to read
def write_val(name, val):
    with open(f'/tmp/agent_{name}', 'w') as f:
        f.write(str(val) if val is not None else '')

write_val('patient_id', qa.get('patient_id', ''))
write_val('modality', qa.get('modality', ''))
write_val('slice_thickness', acq.get('slice_thickness_mm', acq.get('slice_thickness', '')))
write_val('study_date', qa.get('study_date', ''))
write_val('manufacturer', equip.get('manufacturer', qa.get('manufacturer', '')))
write_val('rows', acq.get('rows', ''))
write_val('columns', acq.get('columns', ''))
write_val('slices', acq.get('number_of_slices', acq.get('slices', '')))

# Handle pixel spacing (might be list or single value)
ps = acq.get('pixel_spacing_mm', acq.get('pixel_spacing', []))
if isinstance(ps, list) and len(ps) >= 2:
    write_val('pixel_spacing', f'{ps[0]},{ps[1]}')
elif isinstance(ps, (int, float)):
    write_val('pixel_spacing', f'{ps},{ps}')
else:
    write_val('pixel_spacing', '')

print("Extracted agent values successfully")
PYEOF

    # Read extracted values
    AGENT_PATIENT_ID=$(cat /tmp/agent_patient_id 2>/dev/null || echo "")
    AGENT_MODALITY=$(cat /tmp/agent_modality 2>/dev/null || echo "")
    AGENT_SLICE_THICKNESS=$(cat /tmp/agent_slice_thickness 2>/dev/null || echo "")
    AGENT_PIXEL_SPACING=$(cat /tmp/agent_pixel_spacing 2>/dev/null || echo "")
    AGENT_ROWS=$(cat /tmp/agent_rows 2>/dev/null || echo "")
    AGENT_COLUMNS=$(cat /tmp/agent_columns 2>/dev/null || echo "")
    AGENT_SLICES=$(cat /tmp/agent_slices 2>/dev/null || echo "")
    AGENT_MANUFACTURER=$(cat /tmp/agent_manufacturer 2>/dev/null || echo "")
    AGENT_STUDY_DATE=$(cat /tmp/agent_study_date 2>/dev/null || echo "")
    
    echo "Agent reported: Patient=$AGENT_PATIENT_ID, Modality=$AGENT_MODALITY, SliceThickness=$AGENT_SLICE_THICKNESS"
fi

# Copy ground truth to accessible location for verifier
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_dicom_gt.json" /tmp/dicom_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/dicom_ground_truth.json 2>/dev/null || true

# Copy agent report to accessible location
if [ -f "$OUTPUT_REPORT" ]; then
    cp "$OUTPUT_REPORT" /tmp/agent_dicom_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_dicom_report.json 2>/dev/null || true
fi

# Copy screenshots for verification
if [ -f "$OUTPUT_SCREENSHOT" ]; then
    cp "$OUTPUT_SCREENSHOT" /tmp/agent_screenshot.png 2>/dev/null || true
    chmod 644 /tmp/agent_screenshot.png 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "data_loaded": $DATA_LOADED,
    "volume_count": $VOLUME_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_valid_json": $REPORT_VALID_JSON,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "agent_values": {
        "patient_id": "$AGENT_PATIENT_ID",
        "modality": "$AGENT_MODALITY",
        "slice_thickness_mm": "$AGENT_SLICE_THICKNESS",
        "pixel_spacing_mm": "$AGENT_PIXEL_SPACING",
        "rows": "$AGENT_ROWS",
        "columns": "$AGENT_COLUMNS",
        "number_of_slices": "$AGENT_SLICES",
        "manufacturer": "$AGENT_MANUFACTURER",
        "study_date": "$AGENT_STUDY_DATE"
    },
    "patient_id": "$PATIENT_ID",
    "ground_truth_available": $([ -f "/tmp/dicom_ground_truth.json" ] && echo "true" || echo "false"),
    "final_screenshot_path": "/tmp/dicom_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/dicom_task_result.json 2>/dev/null || sudo rm -f /tmp/dicom_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/dicom_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/dicom_task_result.json
chmod 666 /tmp/dicom_task_result.json 2>/dev/null || sudo chmod 666 /tmp/dicom_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/dicom_task_result.json
echo ""
echo "=== Export Complete ==="