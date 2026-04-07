#!/bin/bash
# Setup script for Blockchain Audit Log task
# Ensures clean state (tries to drop table if exists) and verifies DB readiness

set -e

echo "=== Setting up Blockchain Audit Log Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# --- Pre-flight: Verify Oracle is running ---
echo "[1/3] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container ($ORACLE_CONTAINER) not running!"
    exit 1
fi

# --- Pre-flight: Verify HR schema connectivity ---
echo "[2/3] Verifying HR schema connectivity..."
CONN_OK=0
for attempt in 1 2 3; do
    CONN_TEST=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" 2>/dev/null | tr -d ' ')
    if [[ "$CONN_TEST" =~ ^[0-9]+$ ]] && [ "$CONN_TEST" -ge 1 ]; then
        echo "  HR schema ready."
        CONN_OK=1
        break
    fi
    echo "  Attempt $attempt failed, waiting 5s..."
    sleep 5
done
if [ "$CONN_OK" -eq 0 ]; then
    echo "ERROR: Cannot connect to HR schema."
    exit 1
fi

# --- Clean up prior artifacts ---
# Note: Blockchain tables with retention periods often CANNOT be dropped until retention expires.
# We attempt to drop it. If it fails, the task might be harder (agent has to handle 'already exists'),
# but usually gym environments are reset.
echo "[3/3] Cleaning up artifacts..."
rm -f /home/ga/Desktop/tamper_evidence.txt
rm -f /home/ga/Desktop/latest_signature.txt

# Attempt to drop table if it exists
oracle_query "
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE SALARY_CHANGE_LEDGER CASCADE CONSTRAINTS PURGE';
EXCEPTION
    WHEN OTHERS THEN
        NULL; -- Ignore errors if table doesn't exist or cannot be dropped
END;
/
" "hr" > /dev/null 2>&1 || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="