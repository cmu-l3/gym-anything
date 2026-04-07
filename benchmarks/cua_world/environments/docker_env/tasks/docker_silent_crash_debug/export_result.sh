#!/bin/bash
echo "=== Exporting Silent Crash Debug Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper for screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/acme-sync"
CONTAINER_NAME="acme-sync-worker"

# 1. Check Container Status
CONTAINER_STATUS=$(docker inspect --format '{{.State.Status}}' $CONTAINER_NAME 2>/dev/null || echo "missing")
CONTAINER_RESTARTING=$(docker inspect --format '{{.State.Restarting}}' $CONTAINER_NAME 2>/dev/null || echo "false")
CONTAINER_RUNNING="false"
if [ "$CONTAINER_STATUS" == "running" ] && [ "$CONTAINER_RESTARTING" == "false" ]; then
    CONTAINER_RUNNING="true"
fi

# 2. Check Docker Logs (Observability Fix)
# We expect to see "Inventory sync initialized" in the logs now
LOG_OUTPUT=$(docker logs $CONTAINER_NAME 2>&1 | tail -n 50)
LOGS_VISIBLE="false"
LOGS_CORRECT="false"

if [ -n "$LOG_OUTPUT" ]; then
    LOGS_VISIBLE="true"
    if echo "$LOG_OUTPUT" | grep -q "Inventory sync initialized"; then
        LOGS_CORRECT="true"
    fi
fi

# 3. Check Configuration Fix (docker-compose.yml)
# Should be an integer (100) not string ("100 items")
CONFIG_FIXED="false"
if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    # Look for SYNC_BATCH_SIZE assignment. 
    # Valid: SYNC_BATCH_SIZE=100 or SYNC_BATCH_SIZE: 100 or "100"
    # Invalid: "100 items"
    BATCH_LINE=$(grep "SYNC_BATCH_SIZE" "$PROJECT_DIR/docker-compose.yml" || echo "")
    if echo "$BATCH_LINE" | grep -qv "items"; then
        CONFIG_FIXED="true"
    fi
fi

# 4. Check Documentation
REPORT_PATH="/home/ga/Desktop/reason_for_crash.txt"
REPORT_EXISTS="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
fi

# 5. Check Method of Observability Fix (Code vs Dockerfile vs Symlink)
FIX_METHOD="unknown"
# Check Dockerfile for symlink
if grep -q "ln -sf /dev/stdout" "$PROJECT_DIR/Dockerfile" 2>/dev/null; then
    FIX_METHOD="symlink_dockerfile"
# Check app.py for StreamHandler or stdout
elif grep -q "sys.stdout" "$PROJECT_DIR/app.py" 2>/dev/null || grep -q "StreamHandler" "$PROJECT_DIR/app.py" 2>/dev/null; then
    FIX_METHOD="code_modification"
fi

# Create JSON result
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "container_running": $CONTAINER_RUNNING,
    "container_status": "$CONTAINER_STATUS",
    "logs_visible": $LOGS_VISIBLE,
    "logs_correct_content": $LOGS_CORRECT,
    "config_fixed": $CONFIG_FIXED,
    "report_exists": $REPORT_EXISTS,
    "fix_method": "$FIX_METHOD",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="