#!/bin/bash
echo "=== Setting up Manage Database User task ==="

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

# Drop REPORT_USER if exists from previous attempt
oracle_query "BEGIN EXECUTE IMMEDIATE 'DROP USER report_user CASCADE'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
EXIT;" "system" 2>/dev/null || true
echo "Cleaned up any existing REPORT_USER"

# Record initial user count
INITIAL_USER_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_users WHERE username NOT IN ('SYS','SYSTEM','HR','ANONYMOUS','XDB');" "system" | tr -d '[:space:]')
printf '%s' "$INITIAL_USER_COUNT" > /tmp/initial_user_count
echo "Initial user count: $INITIAL_USER_COUNT"

# Pre-configure System connection for DBA tasks
ensure_hr_connection "System Admin" "system" "$SYSTEM_PWD"

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
