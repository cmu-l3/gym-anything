#!/bin/bash
# Setup task: Query Employee Salary
echo "=== Setting up Query Employee Salary task ==="

source /workspace/scripts/task_utils.sh

date +%s > /home/ga/.task_start_time

# Ensure export directory exists and is clean
mkdir -p /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/finance_high_salary.csv 2>/dev/null || true
rm -f /home/ga/Documents/exports/finance_high_salary.txt 2>/dev/null || true
chown -R ga:ga /home/ga/Documents/exports

# Verify Oracle is running and HR schema loaded
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

EMP_COUNT=$(get_employee_count)
echo "HR schema employees: $EMP_COUNT"
if [ -z "$EMP_COUNT" ] || [ "$EMP_COUNT" -lt 100 ] 2>/dev/null; then
    echo "ERROR: HR schema not properly loaded"
    exit 1
fi

# Verify Finance department data exists
FINANCE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM employees WHERE department_id = 100;" "hr" | tr -d '[:space:]')
echo "Finance department employees: $FINANCE_COUNT"

FINANCE_HIGH_SALARY=$(oracle_query_raw "SELECT COUNT(*) FROM employees WHERE department_id = 100 AND salary > 7000;" "hr" | tr -d '[:space:]')
echo "Finance employees with salary > 7000: $FINANCE_HIGH_SALARY"

# Store ground truth for verification
printf '%s' "$FINANCE_HIGH_SALARY" > /tmp/expected_result_count

# Pre-configure HR Database connection so agent starts connected
ensure_hr_connection "HR Database" "hr" "$HR_PWD"

# Ensure SQL Developer is running, maximized, and connected
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
