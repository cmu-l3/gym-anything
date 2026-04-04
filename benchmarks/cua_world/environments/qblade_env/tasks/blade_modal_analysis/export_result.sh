#!/bin/bash
echo "=== Exporting blade_modal_analysis result ==="

source /workspace/scripts/task_utils.sh

# 1. Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Take final screenshot
take_screenshot /tmp/task_final.png

# 3. Check Project File
PROJECT_PATH="/home/ga/Documents/projects/beam_modal.wpa"
PROJECT_EXISTS="false"
PROJECT_SIZE="0"
STRUCTURAL_DATA_FOUND="false"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during task
    FILE_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Simple grep check for structural keywords in the XML/text project file
    # QBlade saves mass/stiffness distributions in the project file
    if grep -qiE "MassDist|StiffDist|EI_flap|BladeStruct" "$PROJECT_PATH"; then
        STRUCTURAL_DATA_FOUND="true"
    fi
else
    FILE_CREATED_DURING_TASK="false"
fi

# 4. Check JSON Report
JSON_PATH="/home/ga/Documents/modal_results.json"
JSON_EXISTS="false"
REPORTED_MASS="0"
REPORTED_FREQ="0"

if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    # Extract values using simple python one-liner to avoid dependency issues
    REPORTED_MASS=$(python3 -c "import json; print(json.load(open('$JSON_PATH')).get('blade_mass_kg', 0))" 2>/dev/null || echo "0")
    REPORTED_FREQ=$(python3 -c "import json; print(json.load(open('$JSON_PATH')).get('first_eigenfrequency_hz', 0))" 2>/dev/null || echo "0")
fi

# 5. Check if Application is running
APP_RUNNING=$(is_qblade_running)

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size_bytes": $PROJECT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "structural_data_found": $STRUCTURAL_DATA_FOUND,
    "json_report_exists": $JSON_EXISTS,
    "reported_mass": $REPORTED_MASS,
    "reported_freq": $REPORTED_FREQ,
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe copy to output location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="