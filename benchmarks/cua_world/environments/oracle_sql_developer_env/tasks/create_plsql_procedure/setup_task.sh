#!/bin/bash
echo "=== Setting up Create PL/SQL Procedure task ==="

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

# Record initial IT department salaries for verification
IT_SALARY_SUM=$(oracle_query_raw "SELECT SUM(salary) FROM employees WHERE department_id = 60;" "hr" | tr -d '[:space:]')
IT_EMP_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM employees WHERE department_id = 60;" "hr" | tr -d '[:space:]')
printf '%s' "$IT_SALARY_SUM" > /tmp/initial_it_salary_sum
printf '%s' "$IT_EMP_COUNT" > /tmp/initial_it_emp_count
echo "IT department: $IT_EMP_COUNT employees, total salary: $IT_SALARY_SUM"

# Record individual salaries for precise verification
oracle_query_raw "SELECT employee_id || '|' || salary FROM employees WHERE department_id = 60 ORDER BY employee_id;" "hr" > /tmp/initial_it_salaries
echo "Initial IT salaries recorded"

# Drop procedure if exists from previous attempt
oracle_query "BEGIN EXECUTE IMMEDIATE 'DROP PROCEDURE give_department_raise'; EXCEPTION WHEN OTHERS THEN NULL; END;
/
EXIT;" "hr" 2>/dev/null || true

# Record initial procedure count
INITIAL_PROC_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_procedures WHERE object_type = 'PROCEDURE';" "hr" | tr -d '[:space:]')
printf '%s' "$INITIAL_PROC_COUNT" > /tmp/initial_proc_count
echo "Initial procedure count: $INITIAL_PROC_COUNT"

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
