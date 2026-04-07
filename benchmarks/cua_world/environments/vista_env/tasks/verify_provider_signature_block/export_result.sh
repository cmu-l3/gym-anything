#!/bin/bash
# Export script for Verify Provider Signature Block task

echo "=== Exporting Verify Provider Signature Block Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
echo "Final screenshot saved"

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Container Status
VISTA_STATUS="unknown"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "vista-vehu"; then
    VISTA_STATUS="running"
fi
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null || docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)

# 4. Query Ground Truth from Database
# We need to know what the actual signature title is for DFN 1 to verify against VLM
# Structure: ^VA(200, DFN, 20) = "SIG BLOCK CHECKSUM^SIG BLOCK TITLE^SIG BLOCK NAME..."
TARGET_DFN=1
GT_NODE_20=""
GT_TITLE=""
GT_NAME=""

if [ "$VISTA_STATUS" = "running" ]; then
    echo "Querying ground truth for User $TARGET_DFN..."
    
    # Query Node 20
    GT_NODE_20=$(docker exec -u vehu vista-vehu bash -c "source /home/vehu/etc/env && yottadb -run %XCMD 'W \$G(^VA(200,$TARGET_DFN,20))'" 2>/dev/null | tail -1)
    
    if [ -n "$GT_NODE_20" ]; then
        GT_TITLE=$(echo "$GT_NODE_20" | cut -d'^' -f2)
        GT_NAME=$(echo "$GT_NODE_20" | cut -d'^' -f3)
    fi
fi

# Escape JSON strings
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

GT_TITLE_ESC=$(escape_json "$GT_TITLE")
GT_NAME_ESC=$(escape_json "$GT_NAME")
GT_NODE_20_ESC=$(escape_json "$GT_NODE_20")

# 5. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "vista_status": "$VISTA_STATUS",
    "container_ip": "$CONTAINER_IP",
    "ground_truth": {
        "dfn": $TARGET_DFN,
        "node_20_raw": "$GT_NODE_20_ESC",
        "signature_title": "$GT_TITLE_ESC",
        "signature_name": "$GT_NAME_ESC"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export Complete ==="