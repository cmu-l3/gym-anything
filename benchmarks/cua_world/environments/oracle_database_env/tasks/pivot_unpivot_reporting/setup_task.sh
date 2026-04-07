#!/bin/bash
# Setup script for Pivot/Unpivot Reporting task
# Prepares the HR schema with additional tables required for the task.

set -e

echo "=== Setting up Pivot/Unpivot Reporting Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/5] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container ($ORACLE_CONTAINER) not running!"
    exit 1
fi

# --- Pre-flight: Verify HR schema connectivity ---
echo "[2/5] Verifying HR schema connectivity..."
CONN_OK=0
for attempt in 1 2 3; do
    CONN_TEST=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" 2>/dev/null | tr -d ' ')
    if [[ "$CONN_TEST" =~ ^[0-9]+$ ]] && [ "$CONN_TEST" -ge 100 ]; then
        echo "  HR schema ready: $CONN_TEST employees"
        CONN_OK=1
        break
    fi
    echo "  Attempt $attempt failed, waiting 10s..."
    sleep 10
done
if [ "$CONN_OK" -eq 0 ]; then
    echo "ERROR: Cannot connect to HR schema after 3 attempts"
    exit 1
fi

# --- Clean up prior artifacts ---
echo "[3/5] Cleaning up old views and tables..."
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'DROP VIEW DEPT_JOB_SALARY_PIVOT'; EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP VIEW QUARTERLY_SPENDING_PIVOT'; EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP VIEW ANNUAL_COSTS_NORMALIZED'; EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE QUARTERLY_COSTS PURGE'; EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE ANNUAL_SUMMARY_WIDE PURGE'; EXCEPTION WHEN OTHERS THEN NULL;
END;
/
" "hr" > /dev/null 2>&1

rm -f /home/ga/Desktop/dept_job_salary_pivot.csv
rm -f /home/ga/Desktop/quarterly_spending_report.csv
rm -f /home/ga/Desktop/annual_costs_normalized.csv

# --- Create and populate QUARTERLY_COSTS ---
echo "[4/5] Creating QUARTERLY_COSTS table..."
# We derive this from EMPLOYEES and DEPARTMENTS to make it realistic
# Costs: SALARY, BENEFITS (30% salary), EQUIPMENT (fixed), TRAINING (fixed)
# Quarters: Q1 (base), Q2 (base*1.05), Q3 (base*0.95), Q4 (base*1.1)
oracle_query "
CREATE TABLE quarterly_costs (
    department_name VARCHAR2(30),
    quarter VARCHAR2(2),
    cost_category VARCHAR2(20),
    amount NUMBER(10,2)
);

INSERT INTO quarterly_costs
SELECT d.department_name, 'Q1', 'SALARY', SUM(e.salary)*3
FROM employees e JOIN departments d ON e.department_id = d.department_id
GROUP BY d.department_name;

INSERT INTO quarterly_costs
SELECT d.department_name, 'Q2', 'SALARY', SUM(e.salary)*3*1.05
FROM employees e JOIN departments d ON e.department_id = d.department_id
GROUP BY d.department_name;

INSERT INTO quarterly_costs
SELECT d.department_name, 'Q3', 'SALARY', SUM(e.salary)*3*0.95
FROM employees e JOIN departments d ON e.department_id = d.department_id
GROUP BY d.department_name;

INSERT INTO quarterly_costs
SELECT d.department_name, 'Q4', 'SALARY', SUM(e.salary)*3*1.10
FROM employees e JOIN departments d ON e.department_id = d.department_id
GROUP BY d.department_name;

-- Add some other costs to make it interesting
INSERT INTO quarterly_costs
SELECT department_name, quarter, 'BENEFITS', amount * 0.3
FROM quarterly_costs WHERE cost_category = 'SALARY';

INSERT INTO quarterly_costs
SELECT department_name, 'Q1', 'EQUIPMENT', 5000 FROM departments;

INSERT INTO quarterly_costs
SELECT department_name, 'Q3', 'TRAINING', 2000 FROM departments;

COMMIT;
" "hr" > /dev/null 2>&1

QC_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM quarterly_costs;" "hr" | tr -d ' ')
echo "  QUARTERLY_COSTS created with $QC_COUNT rows"

# --- Create and populate ANNUAL_SUMMARY_WIDE ---
echo "[5/5] Creating ANNUAL_SUMMARY_WIDE table..."
oracle_query "
CREATE TABLE annual_summary_wide (
    department_name VARCHAR2(30),
    salary_total NUMBER,
    benefits_total NUMBER,
    equipment_total NUMBER,
    training_total NUMBER
);

INSERT INTO annual_summary_wide
SELECT 
    department_name,
    SUM(CASE WHEN cost_category = 'SALARY' THEN amount ELSE 0 END),
    SUM(CASE WHEN cost_category = 'BENEFITS' THEN amount ELSE 0 END),
    SUM(CASE WHEN cost_category = 'EQUIPMENT' THEN amount ELSE 0 END),
    SUM(CASE WHEN cost_category = 'TRAINING' THEN amount ELSE 0 END)
FROM quarterly_costs
GROUP BY department_name;

COMMIT;
" "hr" > /dev/null 2>&1

ASW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM annual_summary_wide;" "hr" | tr -d ' ')
echo "  ANNUAL_SUMMARY_WIDE created with $ASW_COUNT rows"

# --- Record start time ---
date +%s > /tmp/task_start_time.txt

# --- Take initial screenshot ---
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="