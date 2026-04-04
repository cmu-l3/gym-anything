#!/bin/bash
# Export script for docker_cleanup_selective task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Inspect Containers
# Get all container names and their status
CONTAINER_STATE=$(docker ps -a --format '{{.Names}}|{{.Status}}|{{.State}}')
# Example output: prod-web|Up 5 minutes|running

# 2. Inspect Images
# Check for dangling images count
DANGLING_COUNT=$(docker images -f "dangling=true" -q | wc -l)

# 3. Inspect Volumes
# List all volume names
VOLUME_LIST=$(docker volume ls --format '{{.Name}}' | tr '\n' ',' | sed 's/,$//')

# 4. Inspect Networks
# List all network names
NETWORK_LIST=$(docker network ls --format '{{.Name}}' | tr '\n' ',' | sed 's/,$//')

# 5. Check Report File
REPORT_FILE="/home/ga/cleanup-report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_SIZE=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE")
    # Read first 500 chars for verification, escaped
    REPORT_CONTENT=$(head -c 500 "$REPORT_FILE")
fi

# 6. Anti-gaming timestamps
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
REPORT_MTIME=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
fi
REPORT_CREATED_DURING_TASK="false"
if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
    REPORT_CREATED_DURING_TASK="true"
fi

# 7. Construct JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task": "docker_cleanup_selective",
    "timestamp": "$(date -Iseconds)",
    "container_state_raw": "$(echo "$CONTAINER_STATE" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')",
    "dangling_image_count": $DANGLING_COUNT,
    "volumes": "$VOLUME_LIST",
    "networks": "$NETWORK_LIST",
    "report": {
        "exists": $REPORT_EXISTS,
        "size": $REPORT_SIZE,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "content_preview": "$(echo "$REPORT_CONTENT" | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')"
    },
    "initial_dangling_count": $(cat /tmp/initial_dangling_count 2>/dev/null || echo 0)
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json