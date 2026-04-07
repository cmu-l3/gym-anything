#!/bin/bash
# Export script for docker_cron_observability task

echo "=== Exporting Docker Cron Observability Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CONTAINER_NAME="db-backup"

# 1. Check if container is running
IS_RUNNING=0
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    IS_RUNNING=1
fi

# 2. Check Docker Logs (Observability)
# We look for the success message in the actual docker daemon logs
LOG_CONTENT=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -n 50)
HAS_LOGS=0
if echo "$LOG_CONTENT" | grep -q "Backup payload delivered successfully"; then
    HAS_LOGS=1
fi

# 3. Check Execution Success (Environment Variable Propagation)
# We check if the marker file exists inside the container. 
# This file is ONLY created if the script runs AND API_KEY matches.
EXECUTION_SUCCESS=0
MARKER_TIMESTAMP=0
if [ "$IS_RUNNING" = "1" ]; then
    if docker exec "$CONTAINER_NAME" test -f /tmp/last_backup_success; then
        EXECUTION_SUCCESS=1
        # Read the timestamp from the file to ensure it's recent
        MARKER_DATE=$(docker exec "$CONTAINER_NAME" cat /tmp/last_backup_success)
        # We just trust existence for now, assuming the setup cleared previous ones (it does)
    fi
fi

# 4. Anti-Gaming: Check for Hardcoded Keys
# The agent should NOT hardcode the key in backup.sh or the crontab command
# They should fix the environment inheritance.
HARDCODED_KEY_DETECTED=0

# Check backup.sh inside container
if [ "$IS_RUNNING" = "1" ]; then
    if docker exec "$CONTAINER_NAME" grep -q "production_secret_123" /usr/local/bin/backup.sh; then
        # If they replaced $API_KEY with the literal string in the script
        HARDCODED_KEY_DETECTED=1
    fi
    
    # Check crontab file inside container for hardcoded env var declaration
    # e.g. "API_KEY=production_secret_123" in /etc/cron.d/backup-cron
    if docker exec "$CONTAINER_NAME" grep -q "production_secret_123" /etc/cron.d/backup-cron 2>/dev/null; then
        HARDCODED_KEY_DETECTED=1
    fi
fi

# 5. Check if they are just running the script manually (Cheating)
# We check if cron is actually running as PID 1 or parent
CRON_RUNNING=0
if [ "$IS_RUNNING" = "1" ]; then
    # Check process list
    if docker exec "$CONTAINER_NAME" ps aux | grep -v grep | grep -q "cron"; then
        CRON_RUNNING=1
    fi
fi

# Write results to JSON
cat > /tmp/cron_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "container_running": $IS_RUNNING,
    "logs_visible_in_docker": $HAS_LOGS,
    "script_execution_success": $EXECUTION_SUCCESS,
    "hardcoded_key_detected": $HARDCODED_KEY_DETECTED,
    "cron_process_running": $CRON_RUNNING,
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "Result JSON:"
cat /tmp/cron_result.json
echo "=== Export Complete ==="