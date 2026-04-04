#!/bin/bash
echo "=== Exporting design_high_solidity_rotor result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. define paths
PERF_FILE="/home/ga/Documents/wind_pump_performance.txt"
PROJ_FILE="/home/ga/Documents/projects/wind_pump.wpa"
SUMM_FILE="/home/ga/Documents/design_summary.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check Performance File
PERF_EXISTS="false"
PERF_SIZE=0
PERF_CREATED_DURING="false"
if [ -f "$PERF_FILE" ]; then
    PERF_EXISTS="true"
    PERF_SIZE=$(stat -c%s "$PERF_FILE")
    PERF_MTIME=$(stat -c%Y "$PERF_FILE")
    if [ "$PERF_MTIME" -gt "$START_TIME" ]; then
        PERF_CREATED_DURING="true"
    fi
fi

# 4. Check Project File
PROJ_EXISTS="false"
PROJ_SIZE=0
PROJ_CREATED_DURING="false"
if [ -f "$PROJ_FILE" ]; then
    PROJ_EXISTS="true"
    PROJ_SIZE=$(stat -c%s "$PROJ_FILE")
    PROJ_MTIME=$(stat -c%Y "$PROJ_FILE")
    if [ "$PROJ_MTIME" -gt "$START_TIME" ]; then
        PROJ_CREATED_DURING="true"
    fi
fi

# 5. Check Summary File
SUMM_EXISTS="false"
SUMM_CONTENT=""
if [ -f "$SUMM_FILE" ]; then
    SUMM_EXISTS="true"
    # Read first 200 chars for logging/debugging
    SUMM_CONTENT=$(head -c 200 "$SUMM_FILE" | tr '\n' ' ' | sed 's/"/\\"/g')
fi

# 6. Check if QBlade is running
APP_RUNNING=$(is_qblade_running)
APP_RUNNING_BOOL="false"
if [ "$APP_RUNNING" -gt "0" ]; then
    APP_RUNNING_BOOL="true"
fi

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "perf_file_exists": $PERF_EXISTS,
    "perf_file_size": $PERF_SIZE,
    "perf_created_during_task": $PERF_CREATED_DURING,
    "perf_file_path": "$PERF_FILE",
    "project_file_exists": $PROJ_EXISTS,
    "project_file_size": $PROJ_SIZE,
    "project_created_during_task": $PROJ_CREATED_DURING,
    "summary_file_exists": $SUMM_EXISTS,
    "summary_content": "$SUMM_CONTENT",
    "app_running": $APP_RUNNING_BOOL,
    "task_end_timestamp": $(date +%s)
}
EOF

# 8. Save JSON with permissions
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

# 9. Ensure performance file is readable for the verifier (copy to tmp if needed)
if [ -f "$PERF_FILE" ]; then
    cp "$PERF_FILE" /tmp/task_perf_data.txt
    chmod 644 /tmp/task_perf_data.txt
fi

echo "=== Export complete ==="