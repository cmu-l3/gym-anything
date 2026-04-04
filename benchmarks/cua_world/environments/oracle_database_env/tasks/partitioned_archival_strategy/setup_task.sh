#!/bin/bash
# Setup for partitioned_archival_strategy task
# Ensures clean state: no prior EMPLOYEE_HISTORY_ARCHIVE, MV_DEPT_TURNOVER

set -e

echo "=== Setting up Partitioned Archival Strategy Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "[1/5] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Verify JOB_HISTORY has data ---
echo "[2/5] Verifying JOB_HISTORY source table..."
for attempt in 1 2 3; do
    JH_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM job_history;" "hr" 2>/dev/null | tr -d ' ')
    if [[ "$JH_COUNT" =~ ^[0-9]+$ ]] && [ "$JH_COUNT" -ge 10 ]; then
        echo "  JOB_HISTORY has $JH_COUNT rows — ready"
        break
    fi
    echo "  Attempt $attempt: JOB_HISTORY has $JH_COUNT rows, waiting..."
    sleep 5
    if [ $attempt -eq 3 ]; then
        echo "ERROR: JOB_HISTORY not accessible or empty"
        exit 1
    fi
done

# --- Clean up prior artifacts ---
echo "[3/5] Removing any prior task artifacts..."
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_dept_turnover';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE employee_history_archive CASCADE CONSTRAINTS PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true

rm -f /home/ga/Desktop/archive_analysis.txt

# --- Grant partition privilege if needed (system user) ---
echo "[4/5] Ensuring partitioning and MV privileges..."
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'GRANT CREATE TABLE TO hr';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'GRANT CREATE MATERIALIZED VIEW TO hr';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'GRANT QUERY REWRITE TO hr';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "system" > /dev/null 2>&1 || true

# --- Record baseline ---
echo "[5/5] Recording baseline state..."
date +%s > /tmp/task_start_timestamp
chmod 600 /tmp/task_start_timestamp

echo "${JH_COUNT}" > /tmp/initial_job_history_count_archive
chmod 600 /tmp/initial_job_history_count_archive

# Count all existing user tables for baseline
TABLE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_tables;" "hr" 2>/dev/null | tr -d ' ')
echo "${TABLE_COUNT:-0}" > /tmp/initial_table_count_archive
chmod 600 /tmp/initial_table_count_archive

# Ensure DBeaver is running
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "dbeaver"; then
    su - ga -c "DISPLAY=:1 /snap/bin/dbeaver-ce &" > /dev/null 2>&1 || true
    sleep 6
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Partitioned Archival Strategy Setup Complete ==="
echo "  JOB_HISTORY rows (source): $JH_COUNT"
echo "  EMPLOYEE_HISTORY_ARCHIVE table slot: cleared"
echo "  MV_DEPT_TURNOVER slot: cleared"
echo "  archive_analysis.txt slot: cleared"
