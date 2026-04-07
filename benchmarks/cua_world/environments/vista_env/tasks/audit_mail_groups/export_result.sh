#!/bin/bash
# Export script for Audit Mail Groups task

echo "=== Exporting Audit Mail Groups Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Check VistA/YDBGui Status
VISTA_RUNNING="false"
if docker ps --filter "name=vista-vehu" --filter "status=running" -q 2>/dev/null | grep -q .; then
    VISTA_RUNNING="true"
fi

CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null)
YDBGUI_ACCESSIBLE="false"
if [ -n "$CONTAINER_IP" ]; then
    if curl -s "http://${CONTAINER_IP}:8089/" > /dev/null; then
        YDBGUI_ACCESSIBLE="true"
    fi
fi

# 4. Check Output File
OUTPUT_FILE="/home/ga/Documents/mail_groups_audit.txt"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read content safely, verify valid text
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | head -n 50) # Limit size
fi

# 5. Extract GROUND TRUTH from VistA
# We extract ALL mail group names from ^XMB(3.8) to allow the verifier 
# to check if the agent's reported names are valid.
echo "Extracting ground truth from VistA..."
GROUND_TRUTH_NAMES=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S X=0 F  S X=\$O(^XMB(3.8,X)) Q:X=\"\"  W \$P(\$G(^XMB(3.8,X,0)),\"^\",1),!"' 2>/dev/null)

# Escape JSON strings
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g; s/\r/\\r/g'
}

FILE_CONTENT_ESC=$(escape_json "$FILE_CONTENT")
GROUND_TRUTH_ESC=$(escape_json "$GROUND_TRUTH_NAMES")

# 6. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "vista_running": $VISTA_RUNNING,
    "ydbgui_accessible": $YDBGUI_ACCESSIBLE,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content": "$FILE_CONTENT_ESC",
    "ground_truth_names": "$GROUND_TRUTH_ESC",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions for copy_from_env
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="