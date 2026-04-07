#!/bin/bash
# Setup for FGA Privacy Compliance Audit
# Ensures database is running and cleans up any previous attempts at this specific policy.

set -e

echo "=== Setting up FGA Privacy Compliance Audit ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container ($ORACLE_CONTAINER) not running!"
    exit 1
fi

# --- Pre-flight: Wait for DB connectivity ---
echo "[2/4] Verifying database connectivity..."
wait_for_oracle_ready() {
    for i in {1..12}; do
        if sudo docker exec "$ORACLE_CONTAINER" bash -c "sqlplus -s system/OraclePassword123@localhost:1521/XEPDB1 <<< 'SELECT 1 FROM dual;'" | grep -q "1"; then
            return 0
        fi
        echo "Waiting for DB..."
        sleep 5
    done
    return 1
}

if ! wait_for_oracle_ready; then
    echo "ERROR: Database not reachable."
    exit 1
fi

# --- Clean up prior artifacts ---
echo "[3/4] Cleaning up prior policies and files..."
# Drop the policy if it exists (to ensure clean start)
oracle_query "
BEGIN
  DBMS_FGA.DROP_POLICY(
    object_schema => 'HR',
    object_name   => 'EMPLOYEES',
    policy_name   => 'AUDIT_VIP_ACCESS'
  );
EXCEPTION
  WHEN OTHERS THEN NULL; -- Ignore if policy doesn't exist
END;
/" "system" "OraclePassword123" > /dev/null 2>&1 || true

# Remove evidence file
rm -f /home/ga/Desktop/vip_audit_proof.csv

# --- Capture Initial State ---
echo "[4/4] capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Agent must create policy AUDIT_VIP_ACCESS on HR.EMPLOYEES"