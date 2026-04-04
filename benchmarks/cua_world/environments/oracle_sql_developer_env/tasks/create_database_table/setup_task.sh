#!/bin/bash
# Setup task: Create Database Table
echo "=== Setting up Create Database Table task ==="

source /workspace/scripts/task_utils.sh

date +%s > /home/ga/.task_start_time

# Verify Oracle running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

EMP_COUNT=$(get_employee_count)
echo "HR schema employees: $EMP_COUNT"

# Record initial table count for anti-cheat
INITIAL_TABLE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_tables;" "hr" | tr -d '[:space:]')
printf '%s' "$INITIAL_TABLE_COUNT" > /tmp/initial_table_count
echo "Initial table count: $INITIAL_TABLE_COUNT"

# Drop TRAINING_COURSES if it exists from a previous attempt
oracle_query "BEGIN EXECUTE IMMEDIATE 'DROP TABLE training_courses CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
EXIT;" "hr" 2>/dev/null || true

echo "Verified TRAINING_COURSES does not exist"

# Pre-configure HR Database connection so agent starts connected
ensure_hr_connection "HR Database" "hr" "$HR_PWD"

# Ensure SQL Developer running, maximized, and connected
sleep 2
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "SQL Developer window maximized"
    fi
    open_hr_connection_in_sqldeveloper
else
    echo "WARNING: SQL Developer window not found"
fi

echo "=== Task setup complete ==="
