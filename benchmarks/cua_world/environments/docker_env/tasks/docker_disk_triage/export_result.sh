#!/bin/bash
echo "=== Exporting Docker Disk Triage Results ==="

# Source utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TIMESTAMP=$(date -Iseconds)

# 1. Check Running Production Containers
RUNNING_PROD_COUNT=0
for container in acme-prod-web acme-prod-api acme-prod-db; do
    if [ "$(docker inspect -f '{{.State.Status}}' $container 2>/dev/null)" == "running" ]; then
        ((RUNNING_PROD_COUNT++))
    fi
done

# 2. Check Protected Debug Container Existence
DEBUG_EXISTS=0
if docker ps -a --format '{{.Names}}' | grep -q "^acme-debug-snapshot$"; then
    DEBUG_EXISTS=1
fi

# 3. Check Protected Volume Existence
VOL_PROD_EXISTS=0
if docker volume ls -q | grep -q "^acme-pgdata$"; then
    VOL_PROD_EXISTS=1
fi

# 4. Check Trash Containers (Should be 0)
TRASH_CONTAINER_COUNT=$(docker ps -a --format '{{.Names}}' | grep -E "^(acme-failed-build|acme-old-migration|acme-test-runner-old)" | wc -l)

# 5. Check Trash Volumes (Should be 0)
TRASH_VOLUME_COUNT=$(docker volume ls -q | grep -E "^(acme-redis-data|acme-old-uploads|acme-test-fixtures|acme-build-cache-vol)" | wc -l)

# 6. Check Dangling Images (Should be 0)
DANGLING_IMG_COUNT=$(docker images -f "dangling=true" -q | wc -l)

# 7. Check Report File
REPORT_PATH="/home/ga/Desktop/disk_cleanup_report.txt"
REPORT_EXISTS="false"
REPORT_MODIFIED="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    R_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$R_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED="true"
    fi
fi

# 8. Check Automation Script
SCRIPT_PATH="/home/ga/projects/maintenance/auto_cleanup.sh"
SCRIPT_EXISTS="false"
SCRIPT_EXECUTABLE="false"
SCRIPT_CONTENT=""
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    if [ -x "$SCRIPT_PATH" ]; then
        SCRIPT_EXECUTABLE="true"
    fi
    # Read first 1000 chars for verification (safe from binary garbage)
    SCRIPT_CONTENT=$(head -c 1000 "$SCRIPT_PATH" | base64 -w 0)
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$TIMESTAMP",
    "prod_running_count": $RUNNING_PROD_COUNT,
    "debug_container_exists": $DEBUG_EXISTS,
    "prod_volume_exists": $VOL_PROD_EXISTS,
    "trash_containers_remaining": $TRASH_CONTAINER_COUNT,
    "trash_volumes_remaining": $TRASH_VOLUME_COUNT,
    "dangling_images_remaining": $DANGLING_IMG_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_modified": $REPORT_MODIFIED,
    "script_exists": $SCRIPT_EXISTS,
    "script_executable": $SCRIPT_EXECUTABLE,
    "script_content_b64": "$SCRIPT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="