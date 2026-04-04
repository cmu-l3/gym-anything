#!/bin/bash
# Setup for plsql_hr_analytics task
# Ensures HR schema is clean (no prior HR_ANALYTICS package or COMPENSATION_MATRIX table)

set -e

echo "=== Setting up PL/SQL HR Analytics Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "[1/5] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Verify HR schema ---
echo "[2/5] Verifying HR schema..."
for attempt in 1 2 3; do
    EMP_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" 2>/dev/null | tr -d ' ')
    if [[ "$EMP_COUNT" =~ ^[0-9]+$ ]] && [ "$EMP_COUNT" -ge 100 ]; then
        echo "  HR schema ready: $EMP_COUNT employees"
        break
    fi
    echo "  Attempt $attempt failed, waiting 10s..."
    sleep 10
    if [ $attempt -eq 3 ]; then
        echo "ERROR: Cannot connect to HR schema"
        exit 1
    fi
done

# Verify JOB_GRADES table exists (needed for GRADE_LEVEL logic)
JG_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM job_grades;" "hr" 2>/dev/null | tr -d ' ')
if [ -z "$JG_COUNT" ] || ! [[ "$JG_COUNT" =~ ^[0-9]+$ ]]; then
    echo "WARNING: JOB_GRADES table may not exist or is empty - creating it..."
    oracle_query "
CREATE TABLE job_grades (
    grade_level CHAR(1),
    lowest_sal  NUMBER,
    highest_sal NUMBER,
    CONSTRAINT jg_pk PRIMARY KEY (grade_level)
);
INSERT INTO job_grades VALUES ('A', 1000,  2999);
INSERT INTO job_grades VALUES ('B', 2000,  4999);
INSERT INTO job_grades VALUES ('C', 4000,  7999);
INSERT INTO job_grades VALUES ('D', 7000, 14999);
INSERT INTO job_grades VALUES ('E', 12000, 24999);
COMMIT;
" "hr" > /dev/null 2>&1 || true
fi

# --- Clean up prior artifacts ---
echo "[3/5] Removing any prior task artifacts..."
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'DROP PACKAGE hr_analytics';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE compensation_matrix CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true

rm -f /home/ga/Desktop/compensation_matrix.txt

# --- Record initial state ---
echo "[4/5] Recording baseline state..."
date +%s > /tmp/task_start_timestamp
chmod 600 /tmp/task_start_timestamp

EMP_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" | tr -d ' ')
echo "${EMP_COUNT:-107}" > /tmp/initial_employee_count_plsql
chmod 600 /tmp/initial_employee_count_plsql

# --- Ensure DBeaver is running ---
echo "[5/5] Ensuring DBeaver is available..."
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "dbeaver"; then
    su - ga -c "DISPLAY=:1 /snap/bin/dbeaver-ce &" > /dev/null 2>&1 || true
    sleep 6
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== PL/SQL HR Analytics Setup Complete ==="
echo "  HR schema has $EMP_COUNT employees"
echo "  JOB_GRADES table available for grade level logic"
echo "  HR_ANALYTICS package slot is clear"
echo "  COMPENSATION_MATRIX table slot is clear"
