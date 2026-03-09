#!/bin/bash
echo "=== Setting up Export ER Diagram task ==="

source /workspace/scripts/task_utils.sh

date +%s > /home/ga/.task_start_time

# Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

EMP_COUNT=$(get_employee_count)
echo "HR schema employees: $EMP_COUNT"

# Ensure export directory exists and is clean
mkdir -p /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/hr_schema_diagram.* 2>/dev/null || true
chown -R ga:ga /home/ga/Documents/exports

# Pre-configure HR Database connection so agent starts connected
ensure_hr_connection "HR Database" "hr" "$HR_PWD"

# Ensure SQL Developer running, maximized, and connected
sleep 2
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
    open_hr_connection_in_sqldeveloper
fi

echo "=== Task setup complete ==="
