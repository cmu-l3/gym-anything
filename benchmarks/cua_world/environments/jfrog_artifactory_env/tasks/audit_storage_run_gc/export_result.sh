#!/bin/bash
echo "=== Exporting audit_storage_run_gc result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
REPORT_PATH="/home/ga/storage_audit_report.txt"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Copy report for verifier
    cp "$REPORT_PATH" /tmp/agent_report.txt
    chmod 666 /tmp/agent_report.txt
else
    echo "Report file not found at $REPORT_PATH"
fi

# 3. Get Current Storage Info (Ground Truth for verification)
# We trigger calculation again to get latest stats
curl -s -u admin:password -X POST "http://localhost:8082/artifactory/api/storageinfo/calculate" > /dev/null 2>&1
sleep 2
curl -s -u admin:password "http://localhost:8082/artifactory/api/storageinfo" > /tmp/final_storage_info.json
chmod 666 /tmp/final_storage_info.json

# 4. Get Repository List
curl -s -u admin:password "http://localhost:8082/artifactory/api/repositories" > /tmp/repo_list.json
chmod 666 /tmp/repo_list.json

# 5. Check GC Execution in Logs
# We look for "Garbage collection" messages in the Artifactory log that happened after task start.
# Since docker logs doesn't easily support "since timestamp" in seconds for raw logs, we grep.
# Artifactory logs usually timestamp like "2023-10-27T..."
# A simple grep for the activity is a good proxy, combined with the agent's report.
# We'll save the last 200 lines of logs for the python verifier to parse timestamps if needed.
docker logs artifactory --tail 500 > /tmp/artifactory_full.log 2>&1
grep -i "Garbage collection" /tmp/artifactory_full.log > /tmp/gc_logs.txt || true
chmod 666 /tmp/gc_logs.txt

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json