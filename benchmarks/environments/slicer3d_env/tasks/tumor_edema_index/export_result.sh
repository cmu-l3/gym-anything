#!/bin/bash
echo "=== Exporting Brain Tumor Edema Index Task Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Get sample ID
if [ -f /tmp/edema_task_sample_id.txt ]; then
    SAMPLE_ID=$(cat /tmp/edema_task_sample_id.txt)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
REPORT_PATH="$BRATS_DIR/edema_analysis_report.json"

echo "Sample ID: $SAMPLE_ID"
echo "Expected report path: $REPORT_PATH"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/edema_task_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
else
    echo "Slicer is NOT running"
fi

# Check if report file exists
REPORT_EXISTS="false"
REPORT_VALID_JSON="false"
REPORT_CREATED_DURING_TASK="false"

# Look for report in multiple possible locations
POSSIBLE_REPORT_PATHS=(
    "$REPORT_PATH"
    "$BRATS_DIR/edema_report.json"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/analysis_report.json"
    "/home/ga/Documents/edema_analysis_report.json"
    "/home/ga/edema_analysis_report.json"
)

FOUND_REPORT_PATH=""
for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        FOUND_REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$REPORT_PATH" ]; then
            cp "$path" "$REPORT_PATH" 2>/dev/null || true
        fi
        break
    fi
done

# Validate JSON and check timestamp
if [ "$REPORT_EXISTS" = "true" ] && [ -n "$FOUND_REPORT_PATH" ]; then
    # Check if valid JSON
    if python3 -c "import json; json.load(open('$FOUND_REPORT_PATH'))" 2>/dev/null; then
        REPORT_VALID_JSON="true"
        echo "Report is valid JSON"
    else
        echo "Report is NOT valid JSON"
    fi
    
    # Check timestamp for anti-gaming
    FILE_MTIME=$(stat -c %Y "$FOUND_REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
        echo "Report was created during task (anti-gaming check passed)"
    else
        echo "WARNING: Report timestamp suggests it was NOT created during task"
    fi
fi

# Extract values from agent report if it exists
AGENT_EDEMA_VOL=""
AGENT_CORE_VOL=""
AGENT_PEI=""
AGENT_CLASS=""
AGENT_PATIENT_ID=""

if [ "$REPORT_VALID_JSON" = "true" ] && [ -f "$FOUND_REPORT_PATH" ]; then
    AGENT_EDEMA_VOL=$(python3 -c "import json; d=json.load(open('$FOUND_REPORT_PATH')); print(d.get('edema_volume_ml', ''))" 2>/dev/null || echo "")
    AGENT_CORE_VOL=$(python3 -c "import json; d=json.load(open('$FOUND_REPORT_PATH')); print(d.get('core_volume_ml', ''))" 2>/dev/null || echo "")
    AGENT_PEI=$(python3 -c "import json; d=json.load(open('$FOUND_REPORT_PATH')); print(d.get('pei_ratio', ''))" 2>/dev/null || echo "")
    AGENT_CLASS=$(python3 -c "import json; d=json.load(open('$FOUND_REPORT_PATH')); print(d.get('prognostic_class', ''))" 2>/dev/null || echo "")
    AGENT_PATIENT_ID=$(python3 -c "import json; d=json.load(open('$FOUND_REPORT_PATH')); print(d.get('patient_id', ''))" 2>/dev/null || echo "")
    
    echo ""
    echo "Agent reported values:"
    echo "  Edema volume: $AGENT_EDEMA_VOL mL"
    echo "  Core volume: $AGENT_CORE_VOL mL"
    echo "  PEI ratio: $AGENT_PEI"
    echo "  Prognostic class: $AGENT_CLASS"
    echo "  Patient ID: $AGENT_PATIENT_ID"
fi

# Copy files for verification
echo ""
echo "Preparing files for verification..."

# Copy agent report
if [ -f "$REPORT_PATH" ]; then
    cp "$REPORT_PATH" /tmp/agent_edema_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_edema_report.json 2>/dev/null || true
    echo "Copied agent report to /tmp/agent_edema_report.json"
fi

# Copy ground truth
GT_FILE="$GROUND_TRUTH_DIR/${SAMPLE_ID}_edema_gt.json"
if [ -f "$GT_FILE" ]; then
    cp "$GT_FILE" /tmp/ground_truth_edema.json 2>/dev/null || true
    chmod 644 /tmp/ground_truth_edema.json 2>/dev/null || true
    echo "Copied ground truth to /tmp/ground_truth_edema.json"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/edema_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sample_id": "$SAMPLE_ID",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_sec": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_valid_json": $REPORT_VALID_JSON,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_path": "$REPORT_PATH",
    "found_report_path": "$FOUND_REPORT_PATH",
    "agent_values": {
        "edema_volume_ml": "$AGENT_EDEMA_VOL",
        "core_volume_ml": "$AGENT_CORE_VOL",
        "pei_ratio": "$AGENT_PEI",
        "prognostic_class": "$AGENT_CLASS",
        "patient_id": "$AGENT_PATIENT_ID"
    },
    "screenshot_exists": $([ -f "/tmp/edema_task_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/ground_truth_edema.json" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/edema_task_result.json 2>/dev/null || sudo rm -f /tmp/edema_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/edema_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/edema_task_result.json
chmod 666 /tmp/edema_task_result.json 2>/dev/null || sudo chmod 666 /tmp/edema_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/edema_task_result.json
echo ""
echo "=== Export Complete ==="