#!/bin/bash
# Export script for docker_hardening_readonly task

echo "=== Exporting Hardening Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

CONTAINER_NAME="acme-ingest"
RESULT_FILE="/tmp/hardening_result.json"

# 1. Check if Container is Running
IS_RUNNING=0
STATUS=$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "missing")
if [ "$STATUS" = "running" ]; then
    IS_RUNNING=1
fi

# 2. Check Read-Only Configuration
IS_READONLY=0
RO_CONFIG=$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$CONTAINER_NAME" 2>/dev/null || echo "false")
if [ "$RO_CONFIG" = "true" ]; then
    IS_READONLY=1
fi

# 3. Analyze Mounts
# We use python to parse the JSON array of mounts from inspect
MOUNTS_JSON=$(docker inspect --format '{{json .Mounts}}' "$CONTAINER_NAME" 2>/dev/null || echo "[]")

# Extract specific mount details using python
# We are looking for:
# - Destination: /run/acme OR /run -> Type: tmpfs
# - Destination: /var/lib/acme/cache -> Type: tmpfs
# - Destination: /var/log/acme -> Type: volume
read CACHE_MOUNT_TYPE PID_MOUNT_TYPE LOG_MOUNT_TYPE LOG_MOUNT_NAME <<< $(python3 -c "
import json, sys
try:
    mounts = json.loads('$MOUNTS_JSON')
except:
    mounts = []

cache_type = 'none'
pid_type = 'none'
log_type = 'none'
log_name = ''

for m in mounts:
    dst = m.get('Destination', '')
    mtype = m.get('Type', '')
    name = m.get('Name', '')
    
    # Check Cache
    if dst == '/var/lib/acme/cache':
        cache_type = mtype
        
    # Check PID (could be /run or /run/acme)
    if dst == '/run/acme' or dst == '/run':
        pid_type = mtype
        
    # Check Logs
    if dst == '/var/log/acme':
        log_type = mtype
        log_name = name

print(f'{cache_type} {pid_type} {log_type} {log_name}')
")

# 4. Functional Health Check
HEALTH_CHECK_CODE="000"
if [ "$IS_RUNNING" = "1" ]; then
    HEALTH_CHECK_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health 2>/dev/null || echo "000")
fi
IS_HEALTHY=0
if [ "$HEALTH_CHECK_CODE" = "200" ]; then
    IS_HEALTHY=1
fi

# 5. Check Log Persistence
# If a volume was mounted for logs, check if we can see the log content
LOG_PERSISTED=0
if [ "$LOG_MOUNT_TYPE" = "volume" ] && [ -n "$LOG_MOUNT_NAME" ]; then
    # Inspect the volume content
    # Ideally we'd mount it to check, but we can also just check if the container successfully wrote to it
    # We'll exec into container to check file size if running
    if [ "$IS_RUNNING" = "1" ]; then
        LOG_SIZE=$(docker exec "$CONTAINER_NAME" stat -c %s /var/log/acme/server.log 2>/dev/null || echo "0")
        if [ "$LOG_SIZE" -gt 0 ]; then
            LOG_PERSISTED=1
        fi
    fi
fi

# Write Result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "is_running": $IS_RUNNING,
    "is_readonly": $IS_READONLY,
    "mounts": {
        "cache_type": "$CACHE_MOUNT_TYPE",
        "pid_type": "$PID_MOUNT_TYPE",
        "log_type": "$LOG_MOUNT_TYPE",
        "log_persisted": $LOG_PERSISTED
    },
    "health_status": "$HEALTH_CHECK_CODE",
    "is_healthy": $IS_HEALTHY,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Export results:"
cat "$RESULT_FILE"
echo "=== Export Complete ==="