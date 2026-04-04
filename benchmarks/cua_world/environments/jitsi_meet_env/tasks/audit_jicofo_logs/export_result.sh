#!/bin/bash
set -e
echo "=== Exporting audit_jicofo_logs result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/merger_audit_log.txt"

# 1. Check Output File Status
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Anti-gaming: modified during task?
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# 2. Generate Ground Truth (Hidden from agent during task, exposed now for verification)
# We grep the actual container logs for the meeting name to see what the agent SHOULD have found.
# We look for lines after the task start time roughly (docker logs --since is tricky with loose timestamps, 
# so we'll grab recent logs and filter).
echo "Extracting ground truth logs..."
# Get container name (try likely names)
JICOFO_CONTAINER=$(docker ps --format "{{.Names}}" | grep jicofo | head -n 1)

if [ -n "$JICOFO_CONTAINER" ]; then
    # Grab logs since task start (approx)
    docker logs "$JICOFO_CONTAINER" --since "$(($TASK_END - $TASK_START + 60))s" > /tmp/full_jicofo_logs.txt 2>&1 || true
    
    # Filter for the meeting name
    grep -i "MergerDiscussion" /tmp/full_jicofo_logs.txt > /tmp/ground_truth_matches.txt || true
    GROUND_TRUTH_COUNT=$(wc -l < /tmp/ground_truth_matches.txt)
else
    echo "WARNING: Jicofo container not found"
    GROUND_TRUTH_COUNT="0"
fi

# 3. Check if Meeting was actually active (Secondary signal)
# We can check if the room currently exists in the API or logs
ROOM_ACTIVE="false"
if grep -q "MergerDiscussion" /tmp/full_jicofo_logs.txt; then
    ROOM_ACTIVE="true"
fi

# 4. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "room_active_in_logs": $ROOM_ACTIVE,
    "ground_truth_log_count": $GROUND_TRUTH_COUNT,
    "jicofo_container_found": $([ -n "$JICOFO_CONTAINER" ] && echo "true" || echo "false")
}
EOF

# Move result JSON
rm -f /tmp/task_result.json
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy ground truth files for the verifier to access via copy_from_env
cp /tmp/ground_truth_matches.txt /tmp/ground_truth_logs.txt
chmod 666 /tmp/ground_truth_logs.txt 2>/dev/null || true
chmod 666 "$OUTPUT_FILE" 2>/dev/null || true

echo "=== Export complete ==="