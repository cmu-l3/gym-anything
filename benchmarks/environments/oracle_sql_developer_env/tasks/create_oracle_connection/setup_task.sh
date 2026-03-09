#!/bin/bash
# Setup task: Create Oracle Connection
echo "=== Setting up Create Oracle Connection task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running (status: $CONTAINER_STATUS)"
    exit 1
fi

# Verify HR schema accessible
EMP_COUNT=$(get_employee_count)
echo "Oracle HR schema: $EMP_COUNT employees"
if [ -z "$EMP_COUNT" ] || [ "$EMP_COUNT" -lt 100 ] 2>/dev/null; then
    echo "ERROR: HR schema not properly loaded"
    exit 1
fi

# Record initial connection count (for anti-cheat)
# SQL Developer 24.3 uses connections.json, older versions use connections.xml
INITIAL_CONN_COUNT=0
CONN_FILE=$(find /home/ga/.sqldeveloper -name "connections.json" -type f 2>/dev/null | head -1)
if [ -n "$CONN_FILE" ] && [ -f "$CONN_FILE" ]; then
    INITIAL_CONN_COUNT=$(grep -c '"name"' "$CONN_FILE" 2>/dev/null || true)
else
    CONN_FILE=$(find /home/ga/.sqldeveloper -name "connections.xml" -type f 2>/dev/null | head -1)
    if [ -n "$CONN_FILE" ] && [ -f "$CONN_FILE" ]; then
        INITIAL_CONN_COUNT=$(grep -c '<Reference' "$CONN_FILE" 2>/dev/null || true)
    fi
fi
printf '%s' "$INITIAL_CONN_COUNT" > /tmp/initial_conn_count

# Ensure SQL Developer is running and maximized
sleep 2
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "SQL Developer window maximized"
    fi
else
    echo "WARNING: SQL Developer window not found"
fi

echo "=== Task setup complete ==="
