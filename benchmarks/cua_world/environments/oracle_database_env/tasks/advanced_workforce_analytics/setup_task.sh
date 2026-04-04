#!/bin/bash
# Setup for advanced_workforce_analytics task
# Verifies HR schema is intact and clears prior output file

set -e

echo "=== Setting up Advanced Workforce Analytics Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Verify HR schema tables ---
echo "[2/4] Verifying HR schema integrity..."
for attempt in 1 2 3; do
    EMP_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" 2>/dev/null | tr -d ' ')
    JH_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM job_history;" "hr" 2>/dev/null | tr -d ' ')
    DEPT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM departments;" "hr" 2>/dev/null | tr -d ' ')
    LOC_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM locations;" "hr" 2>/dev/null | tr -d ' ')
    if [[ "$EMP_COUNT" =~ ^[0-9]+$ ]] && [ "$EMP_COUNT" -ge 100 ] && \
       [[ "$JH_COUNT" =~ ^[0-9]+$ ]] && [ "$JH_COUNT" -ge 5 ]; then
        echo "  HR schema ready: $EMP_COUNT employees, $JH_COUNT job_history rows, $DEPT_COUNT depts, $LOC_COUNT locations"
        break
    fi
    echo "  Attempt $attempt: employees=$EMP_COUNT, job_history=$JH_COUNT — retrying..."
    sleep 5
    if [ $attempt -eq 3 ]; then
        echo "ERROR: HR schema not ready"
        exit 1
    fi
done

# --- Clean up prior output ---
echo "[3/4] Removing prior output file..."
rm -f /home/ga/Desktop/workforce_analytics_report.txt

# Pre-compute ground truth answers and store them for verifier validation
python3 << 'PYEOF'
import oracledb
import json

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Q1: City with highest average salary
    cursor.execute("""
        SELECT l.city, ROUND(AVG(e.salary), 2) AS avg_sal
        FROM employees e
        JOIN departments d ON e.department_id = d.department_id
        JOIN locations l ON d.location_id = l.location_id
        GROUP BY l.city
        ORDER BY avg_sal DESC
        FETCH FIRST 1 ROW ONLY
    """)
    row = cursor.fetchone()
    q1 = {"city": str(row[0]) if row else None, "avg_salary": float(row[1]) if row else None}

    # Q2: Manager with widest span
    cursor.execute("""
        SELECT e.employee_id, e.first_name || ' ' || e.last_name AS full_name,
               COUNT(r.employee_id) AS report_count
        FROM employees e
        JOIN employees r ON r.manager_id = e.employee_id
        GROUP BY e.employee_id, e.first_name, e.last_name
        ORDER BY report_count DESC
        FETCH FIRST 1 ROW ONLY
    """)
    row = cursor.fetchone()
    q2 = {"manager_name": str(row[1]) if row else None, "report_count": int(row[2]) if row else None}

    # Q3: Average salary increase % on job change
    # Uses JOB_HISTORY to find employees who have changed jobs
    # Compares: for each completed job change (in job_history), employee's current salary vs
    # the salary they had when that job ended (we approximate using current salary since
    # historical salaries aren't stored — so we compare salary progression via department)
    # More precisely: average % salary delta across all employees who appear in job_history
    cursor.execute("""
        WITH job_changes AS (
            SELECT jh.employee_id,
                   jh.end_date,
                   e.salary AS current_salary,
                   j_old.min_salary AS old_job_min,
                   j_old.max_salary AS old_job_max,
                   j_new.min_salary AS new_job_min,
                   j_new.max_salary AS new_job_max
            FROM job_history jh
            JOIN employees e ON jh.employee_id = e.employee_id
            JOIN jobs j_old ON jh.job_id = j_old.job_id
            JOIN jobs j_new ON e.job_id = j_new.job_id
            WHERE j_old.min_salary > 0
        )
        SELECT ROUND(AVG(
            ((new_job_min - old_job_min) / NULLIF(old_job_min, 0)) * 100
        ), 2) AS avg_increase_pct
        FROM job_changes
    """)
    row = cursor.fetchone()
    q3 = {"avg_salary_increase_pct": float(row[0]) if row and row[0] is not None else None}

    # Q4: Most mobile job title (most distinct employees who held it)
    cursor.execute("""
        WITH all_jobs AS (
            SELECT employee_id, job_id FROM employees
            UNION ALL
            SELECT employee_id, job_id FROM job_history
        )
        SELECT j.job_title, COUNT(DISTINCT a.employee_id) AS emp_count
        FROM all_jobs a
        JOIN jobs j ON a.job_id = j.job_id
        GROUP BY j.job_title
        ORDER BY emp_count DESC
        FETCH FIRST 1 ROW ONLY
    """)
    row = cursor.fetchone()
    q4 = {"job_title": str(row[0]) if row else None, "employee_count": int(row[1]) if row else None}

    answers = {"q1": q1, "q2": q2, "q3": q3, "q4": q4}
    with open("/tmp/workforce_analytics_ground_truth.json", "w") as f:
        json.dump(answers, f, indent=2)

    print("Ground truth computed:")
    print(f"  Q1: {q1}")
    print(f"  Q2: {q2}")
    print(f"  Q3: {q3}")
    print(f"  Q4: {q4}")

    cursor.close()
    conn.close()
except Exception as e:
    print(f"WARNING: Could not compute ground truth: {e}")
    # Write empty ground truth to avoid missing file
    with open("/tmp/workforce_analytics_ground_truth.json", "w") as f:
        json.dump({}, f)
PYEOF
chmod 600 /tmp/workforce_analytics_ground_truth.json

# --- Record baseline ---
echo "[4/4] Recording baseline state..."
date +%s > /tmp/task_start_timestamp
chmod 600 /tmp/task_start_timestamp

echo "$EMP_COUNT" > /tmp/initial_employee_count_analytics
chmod 600 /tmp/initial_employee_count_analytics

# Ensure DBeaver is running
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "dbeaver"; then
    su - ga -c "DISPLAY=:1 /snap/bin/dbeaver-ce &" > /dev/null 2>&1 || true
    sleep 6
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Advanced Workforce Analytics Setup Complete ==="
echo "  Employees: $EMP_COUNT"
echo "  Job history rows: $JH_COUNT"
echo "  Departments: $DEPT_COUNT"
echo "  Locations: $LOC_COUNT"
echo "  Output file slot: cleared"
