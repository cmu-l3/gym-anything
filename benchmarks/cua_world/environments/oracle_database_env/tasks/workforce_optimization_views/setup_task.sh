#!/bin/bash
# Setup script for Workforce Optimization Views task
# Ensures Oracle is running, HR schema is clean (drops target views/tables if they exist)

set -e

echo "=== Setting up Workforce Optimization Views Task ==="

source /workspace/scripts/task_utils.sh

# --- 1. Pre-flight Checks ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

echo "[2/4] Verifying HR schema connectivity..."
for attempt in 1 2 3; do
    CONN_TEST=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" 2>/dev/null | tr -d ' ')
    if [[ "$CONN_TEST" =~ ^[0-9]+$ ]] && [ "$CONN_TEST" -ge 100 ]; then
        echo "  HR schema ready: $CONN_TEST employees"
        break
    fi
    echo "  Attempt $attempt failed, waiting 10s..."
    sleep 10
    if [ $attempt -eq 3 ]; then
        echo "ERROR: Cannot connect to HR schema"
        exit 1
    fi
done

# --- 2. Clean Environment ---
echo "[3/4] cleaning up previous task artifacts..."

# Drop the views and tables if they exist to ensure a fresh start
oracle_query "
BEGIN
    EXECUTE IMMEDIATE 'DROP VIEW ORG_HIERARCHY_VW';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP VIEW SALARY_BAND_ANALYTICS_VW';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE DEPT_JOB_CROSSTAB PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
COMMIT;
" "hr" > /dev/null 2>&1

# Remove CSV files
rm -f /home/ga/Desktop/org_hierarchy.csv
rm -f /home/ga/Desktop/salary_analytics.csv
rm -f /home/ga/Desktop/dept_job_matrix.csv

# --- 3. Initial State Recording ---
echo "[4/4] Recording baseline state..."
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

# Ensure DBeaver is installed (standard env usually has it, but good to check)
if ! which dbeaver-ce > /dev/null 2>&1; then
    echo "WARNING: DBeaver not found in path, agent might need to use sqlplus or find it."
fi

echo "=== Setup Complete ==="
echo "Artifacts cleaned. Database ready."