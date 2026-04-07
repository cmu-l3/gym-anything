#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture the final state of all devices (containing schedules) from the API
echo "Exporting final API state..."
refresh_nx_token > /dev/null
nx_api_get "/rest/v1/devices" > /tmp/final_devices_state.json

# 2. Check the report file
REPORT_PATH="/home/ga/recording_schedule_report.txt"
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
fi

# 3. Take a final screenshot
take_screenshot /tmp/task_final.png

# 4. Construct result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "report_size_bytes": $REPORT_SIZE,
    "report_content_snippet": $([ -f "$REPORT_PATH" ] && head -n 20 "$REPORT_PATH" | jq -R -s '.' || echo "\"\""),
    "api_devices_dump_path": "/tmp/final_devices_state.json",
    "initial_devices_dump_path": "/tmp/initial_devices_state.json"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Ensure the dump files are readable by the verifier (which runs as root/verifier)
chmod 644 /tmp/final_devices_state.json 2>/dev/null || true
chmod 644 /tmp/initial_devices_state.json 2>/dev/null || true

echo "=== Export complete ==="