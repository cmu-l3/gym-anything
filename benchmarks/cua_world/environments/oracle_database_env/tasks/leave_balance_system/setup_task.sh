#!/bin/bash
# Setup script for Leave Balance System task
# Ensures HR schema is ready and cleans up any prior run artifacts

set -e

echo "=== Setting up Leave Balance System Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Verify HR schema connectivity ---
echo "[2/4] Verifying HR schema connectivity..."
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

# --- Clean up prior artifacts ---
echo "[3/4] Cleaning up previous task artifacts..."
oracle_query "
BEGIN
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE leave_requests CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE leave_balances CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE leave_policies CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP PROCEDURE calculate_leave_accruals'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/" "hr" > /dev/null 2>&1 || true

rm -f /home/ga/Desktop/leave_balance_report.txt

# --- Record start time ---
echo "[4/4] Recording start time..."
date +%s > /tmp/task_start_timestamp

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="