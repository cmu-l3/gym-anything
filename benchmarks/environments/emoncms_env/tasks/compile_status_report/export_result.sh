#!/bin/bash
echo "=== Exporting compile_status_report results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Task Timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check Agent's Output File
REPORT_FILE="/home/ga/emoncms_status_report.json"
REPORT_EXISTS="false"
REPORT_VALID="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Simple validity check (is it valid JSON?)
    if jq empty "$REPORT_FILE" >/dev/null 2>&1; then
        REPORT_VALID="true"
    fi
fi

# 3. Capture Ground Truth (Snapshot of DB at task end)
# We fetch the actual feed list from the local API to compare against agent's report
# We use the admin API key to ensure we see everything
APIKEY=$(get_apikey_write)
GROUND_TRUTH_FILE="/tmp/ground_truth_feeds.json"
curl -s "${EMONCMS_URL}/feed/list.json?apikey=${APIKEY}" > "$GROUND_TRUTH_FILE"

# 4. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result Manifest
# We won't embed the full huge JSONs here, but we will point to them
# The verifier will copy the actual files
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_valid_json": $REPORT_VALID,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_path": "$REPORT_FILE",
    "ground_truth_path": "$GROUND_TRUTH_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result manifest saved to /tmp/task_result.json"