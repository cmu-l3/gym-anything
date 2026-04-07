#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting export_exam_config_file results ==="

# Take final screenshot
take_screenshot /tmp/final_screenshot.png

START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# Look for downloaded .seb file
SEB_FILE=$(find /home/ga/Downloads -name "*.seb" -type f | head -n 1)

FILE_EXISTS="false"
FILE_NAME=""
FILE_SIZE=0
FILE_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -n "$SEB_FILE" ]; then
    FILE_EXISTS="true"
    FILE_NAME=$(basename "$SEB_FILE")
    FILE_SIZE=$(stat -c %s "$SEB_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$SEB_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if the configuration still exists in the database (prevent agent from deleting it)
CONFIG_EXISTS_DB=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM configuration_node WHERE name='Anatomy Midterm Config' AND type='EXAM_CONFIG'" 2>/dev/null || echo "0")

CONFIG_STILL_EXISTS="false"
if [ "$CONFIG_EXISTS_DB" -gt 0 ]; then
    CONFIG_STILL_EXISTS="true"
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $START_TIME,
    "task_end_time": $END_TIME,
    "file_exists": $FILE_EXISTS,
    "file_name": "$FILE_NAME",
    "file_size_bytes": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "config_still_exists_in_db": $CONFIG_STILL_EXISTS
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="