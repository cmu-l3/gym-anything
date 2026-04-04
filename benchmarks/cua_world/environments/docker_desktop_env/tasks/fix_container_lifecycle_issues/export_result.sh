#!/bin/bash
# Export script for fix_container_lifecycle_issues
# Performs active checks (shutdown timing, log flow) and exports JSON

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/Documents/docker-projects/order-processor"
CONTAINER_NAME="order-processor"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_end.png

# --- 1. CONFIGURATION CHECK (Static) ---
# Check if init is enabled in inspect
INIT_ENABLED=$(docker inspect "$CONTAINER_NAME" --format '{{.HostConfig.Init}}' 2>/dev/null || echo "false")

# Check for unbuffered env var
ENV_VARS=$(docker inspect "$CONTAINER_NAME" --format '{{json .Config.Env}}' 2>/dev/null)
if echo "$ENV_VARS" | grep -q "PYTHONUNBUFFERED"; then
    UNBUFFERED_ENV="true"
else
    UNBUFFERED_ENV="false"
fi

# Check command line for -u flag (alternative fix for buffering)
CMD_STR=$(docker inspect "$CONTAINER_NAME" --format '{{json .Config.Cmd}}' 2>/dev/null)
ENTRYPOINT_STR=$(docker inspect "$CONTAINER_NAME" --format '{{json .Config.Entrypoint}}' 2>/dev/null)
if [[ "$CMD_STR" == *"-u"* ]] || [[ "$ENTRYPOINT_STR" == *"-u"* ]]; then
    UNBUFFERED_FLAG="true"
else
    UNBUFFERED_FLAG="false"
fi

# --- 2. LOG LATENCY CHECK (Active) ---
echo "Checking log latency..."
# Ensure container is running
if ! container_running "$CONTAINER_NAME"; then
    su - ga -c "cd $PROJECT_DIR && docker compose up -d"
    sleep 3
fi

# Capture logs, wait, capture again.
# The script prints every 2 seconds.
LOGS_BEFORE=$(docker logs "$CONTAINER_NAME" 2>&1 | wc -l)
sleep 4
LOGS_AFTER=$(docker logs "$CONTAINER_NAME" 2>&1 | wc -l)

LOGS_INCREASED="false"
if [ "$LOGS_AFTER" -gt "$LOGS_BEFORE" ]; then
    LOGS_INCREASED="true"
    echo "Logs increased: $LOGS_BEFORE -> $LOGS_AFTER (Good)"
else
    echo "Logs did not increase: $LOGS_BEFORE -> $LOGS_AFTER (Buffered or Stuck)"
fi

# --- 3. SHUTDOWN TIMING CHECK (Active) ---
echo "Checking shutdown timing..."
# We measure the time it takes to stop the service
START_TIME=$(date +%s%N)
su - ga -c "cd $PROJECT_DIR && docker compose stop"
END_TIME=$(date +%s%N)

# Calculate duration in seconds (floating point)
DURATION_NS=$((END_TIME - START_TIME))
# Handle potential negative if clock skew (unlikely)
if [ "$DURATION_NS" -lt 0 ]; then DURATION_NS=0; fi
DURATION_SEC=$(echo "scale=3; $DURATION_NS / 1000000000" | bc)

echo "Shutdown took: ${DURATION_SEC}s"

# Clean up (restart for user if they want to check again? No, task is done)

# --- 4. EXPORT JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config": {
        "init_enabled": $INIT_ENABLED,
        "unbuffered_env": $UNBUFFERED_ENV,
        "unbuffered_flag": $UNBUFFERED_FLAG
    },
    "behavior": {
        "logs_streaming": $LOGS_INCREASED,
        "shutdown_duration_sec": $DURATION_SEC
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE"
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"