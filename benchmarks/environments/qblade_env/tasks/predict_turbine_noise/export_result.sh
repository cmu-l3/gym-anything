#!/bin/bash
echo "=== Exporting predict_turbine_noise result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- Verify Noise Data File ---
DATA_FILE="/home/ga/Documents/noise_spectrum_output.txt"
DATA_EXISTS="false"
DATA_SIZE=0
DATA_LINES=0
DATA_CREATED_IN_TASK="false"
HAS_FREQ_COL="false"
HAS_SPL_COL="false"
VALID_VALUE_RANGE="false"

if [ -f "$DATA_FILE" ]; then
    DATA_EXISTS="true"
    DATA_SIZE=$(stat -c%s "$DATA_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$DATA_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        DATA_CREATED_IN_TASK="true"
    fi
    
    # Content analysis
    DATA_LINES=$(grep -cE "^[[:space:]]*[0-9]" "$DATA_FILE" 2>/dev/null || echo "0")
    
    # Check for likely headers or data format (Frequency / SPL / dBA)
    if grep -qiE "freq|Hz" "$DATA_FILE"; then HAS_FREQ_COL="true"; fi
    if grep -qiE "SPL|dB|Sound" "$DATA_FILE"; then HAS_SPL_COL="true"; fi
    
    # Basic value sanity check: Are there values between 10 and 150 (dB)?
    # We look for a number between 10.0 and 150.0 in the file
    if grep -qE "[1-9][0-9]\.[0-9]+" "$DATA_FILE"; then
        VALID_VALUE_RANGE="true"
    fi
fi

# --- Verify Project File ---
PROJ_FILE="/home/ga/Documents/projects/turbine_noise_analysis.wpa"
PROJ_EXISTS="false"
PROJ_SIZE=0
PROJ_CREATED_IN_TASK="false"

if [ -f "$PROJ_FILE" ]; then
    PROJ_EXISTS="true"
    PROJ_SIZE=$(stat -c%s "$PROJ_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$PROJ_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        PROJ_CREATED_IN_TASK="true"
    fi
fi

# Check application state
APP_RUNNING=$(is_qblade_running)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "data_file": {
        "exists": $DATA_EXISTS,
        "created_during_task": $DATA_CREATED_IN_TASK,
        "size_bytes": $DATA_SIZE,
        "lines_of_data": $DATA_LINES,
        "has_freq_header": $HAS_FREQ_COL,
        "has_spl_header": $HAS_SPL_COL,
        "has_valid_values": $VALID_VALUE_RANGE
    },
    "project_file": {
        "exists": $PROJ_EXISTS,
        "created_during_task": $PROJ_CREATED_IN_TASK,
        "size_bytes": $PROJ_SIZE
    },
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
write_result_json "$(cat $TEMP_JSON)" "/tmp/task_result.json"
rm -f "$TEMP_JSON"

echo "=== Export complete ==="