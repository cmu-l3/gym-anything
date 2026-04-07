#!/bin/bash
echo "=== Exporting Docker Event Automation Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timings
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Define paths
PROJECT_DIR="/home/ga/projects/watchdog"
SCRIPT_PATH="$PROJECT_DIR/watchdog.py"
LOG_PATH="$PROJECT_DIR/watchdog.log"
ALERT_PATH="$PROJECT_DIR/alert.txt"

# 4. Check file existence
SCRIPT_EXISTS="false"
[ -f "$SCRIPT_PATH" ] && SCRIPT_EXISTS="true"

LOG_EXISTS="false"
[ -f "$LOG_PATH" ] && LOG_EXISTS="true"

ALERT_EXISTS="false"
[ -f "$ALERT_PATH" ] && ALERT_EXISTS="true"

# 5. Check container state
# Expected: "exited" if circuit breaker tripped
CONTAINER_STATUS=$(docker inspect payment-gateway --format '{{.State.Status}}' 2>/dev/null || echo "missing")
CONTAINER_RESTART_COUNT=$(docker inspect payment-gateway --format '{{.RestartCount}}' 2>/dev/null || echo "0")

# 6. Check Alert Content
ALERT_CONTENT=""
if [ "$ALERT_EXISTS" = "true" ]; then
    ALERT_CONTENT=$(cat "$ALERT_PATH" | head -n 1)
fi

# 7. Check Log Content
# Read last 5 lines
LOG_CONTENT=""
if [ "$LOG_EXISTS" = "true" ]; then
    LOG_CONTENT=$(tail -n 5 "$LOG_PATH" | base64 -w 0)
fi

# 8. Dump Docker Events (CRITICAL for verification)
# We want to see the sequence of 'die' and 'start' events for the container
echo "Dumping docker events..."
EVENTS_JSON="/tmp/docker_events.json"
# We fetch events since task start.
# Format as JSON Lines for easy parsing in python
docker events \
    --since "$TASK_START" \
    --until "$TASK_END" \
    --filter "container=payment-gateway" \
    --filter "event=die" \
    --filter "event=start" \
    --format '{{json .}}' > "$EVENTS_JSON" || true

# Encode events file to base64 to embed in result JSON safely
EVENTS_B64=$(cat "$EVENTS_JSON" | base64 -w 0)

# 9. Construct Result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "log_exists": $LOG_EXISTS,
    "alert_exists": $ALERT_EXISTS,
    "container_status": "$CONTAINER_STATUS",
    "container_restart_count": $CONTAINER_RESTART_COUNT,
    "alert_content": "$(json_escape "$ALERT_CONTENT")",
    "log_content_b64": "$LOG_CONTENT",
    "docker_events_b64": "$EVENTS_B64",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="