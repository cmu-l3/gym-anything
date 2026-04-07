#!/bin/bash
# Setup script for Logistics AQ Setup task
# Ensures clean state by removing any existing AQ objects in HR schema

set -e
echo "=== Setting up Logistics AQ Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# --- Pre-flight: Verify Oracle is running ---
echo "[1/3] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Wait for Database Connectivity ---
echo "[2/3] Verifying database connectivity..."
for i in {1..10}; do
    if oracle_query_raw "SELECT 1 FROM DUAL;" "system" >/dev/null 2>&1; then
        echo "Database is ready."
        break
    fi
    echo "Waiting for database..."
    sleep 5
done

# --- Clean up previous state ---
echo "[3/3] Cleaning up previous artifacts..."
# We run a PL/SQL block to drop objects if they exist.
# We must do this as SYSTEM to have force privileges or assume HR ownership.
# Using HR user for cleanup of its own objects.

sudo docker exec -i "$ORACLE_CONTAINER" sqlplus -s hr/hr123@localhost:1521/XEPDB1 << 'EOF'
SET SERVEROUTPUT ON
BEGIN
    -- Stop and Drop Queue
    BEGIN
        DBMS_AQADM.STOP_QUEUE(queue_name => 'ORDER_EVT_Q');
        DBMS_AQADM.DROP_QUEUE(queue_name => 'ORDER_EVT_Q');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- Drop Queue Table
    BEGIN
        DBMS_AQADM.DROP_QUEUE_TABLE(queue_table => 'ORDER_EVT_QT');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- Drop Procedure
    BEGIN
        EXECUTE IMMEDIATE 'DROP PROCEDURE ENQUEUE_ORDER';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- Drop Type
    BEGIN
        EXECUTE IMMEDIATE 'DROP TYPE ORDER_EVENT_T FORCE';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
END;
/
EXIT;
EOF

# Revoke privileges from HR to ensure agent has to grant them (optional, but good for completeness)
# sudo docker exec -i "$ORACLE_CONTAINER" sqlplus -s system/OraclePassword123@localhost:1521/XEPDB1 << 'EOF'
# REVOKE EXECUTE ON DBMS_AQ FROM HR;
# REVOKE EXECUTE ON DBMS_AQADM FROM HR;
# EXIT;
# EOF
# Note: Revoking might break other things if shared env, so skipping strictly to avoid side effects, 
# but the task requires the agent to "ensure" they have them or grant them. 
# Since HR usually doesn't have AQ rights by default in XE, the task is valid.

# Remove output file
rm -f /home/ga/Desktop/queue_dump.txt

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="