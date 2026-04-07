#!/bin/bash
# Setup for Compound Trigger Budget Protection task
# Resets HR schema to a clean state and ensures no prior budget objects exist.

set -e

echo "=== Setting up Compound Trigger Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Verify HR schema connectivity ---
echo "[2/4] Verifying HR schema connectivity..."
for attempt in 1 2 3; do
    CONN_TEST=$(oracle_query_raw "SELECT 'OK' FROM DUAL;" "hr" 2>/dev/null | grep OK || echo "")
    if [ "$CONN_TEST" == "OK" ]; then
        echo "  Database ready."
        break
    fi
    echo "  Attempt $attempt failed, waiting 10s..."
    sleep 10
    if [ $attempt -eq 3 ]; then
        echo "ERROR: Cannot connect to HR schema"
        exit 1
    fi
done

# --- Reset Data State ---
echo "[3/4] Resetting data state..."
# Drop the objects if they exist from previous runs
oracle_query "
BEGIN
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE dept_spending_caps CASCADE CONSTRAINTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TRIGGER trg_enforce_spending_cap'; EXCEPTION WHEN OTHERS THEN NULL; END;
    -- Reset a specific employee used for testing to known salary
    UPDATE employees SET salary = 4800, department_id = 60 WHERE employee_id = 103;
    COMMIT;
END;
/" "hr" > /dev/null 2>&1

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# --- Ensure DBeaver/SQL Developer is ready ---
echo "[4/4] Ensuring environment ready..."
# We don't force-launch a tool, but we ensure the environment is clean
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "HR Schema reset. Ready for task."