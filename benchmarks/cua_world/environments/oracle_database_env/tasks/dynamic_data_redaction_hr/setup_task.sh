#!/bin/bash
# Setup for Dynamic Data Redaction Task
# Ensures clean state by removing the target user and any existing redaction policies

set -e

echo "=== Setting up Dynamic Data Redaction Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Wait for Database to be ready ---
echo "[2/4] Verifying database connectivity..."
for i in {1..30}; do
    if oracle_query_raw "SELECT 1 FROM DUAL;" "system" >/dev/null 2>&1; then
        echo "Database is ready."
        break
    fi
    echo "Waiting for database... $i"
    sleep 2
done

# --- Clean Clean State ---
echo "[3/4] Cleaning up previous task artifacts..."
python3 << 'PYEOF'
import oracledb
import sys

try:
    conn = oracledb.connect(user="system", password="OraclePassword123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Drop User QA_TESTER if exists
    try:
        cursor.execute("DROP USER QA_TESTER CASCADE")
        print("Dropped user QA_TESTER")
    except oracledb.DatabaseError as e:
        if "ORA-01918" not in str(e): # ORA-01918: user does not exist
            print(f"Warning dropping user: {e}")

    # 2. Drop existing Redaction Policies on HR.EMPLOYEES
    # We need to find them first
    cursor.execute("""
        SELECT policy_name 
        FROM redirection_policies 
        WHERE object_owner = 'HR' AND object_name = 'EMPLOYEES'
    """) 
    # Note: View name is REDACTION_POLICIES, but might need checking ALL_REDACTION_POLICIES
    # Simpler: Just try to drop specific named policies if we knew them, 
    # but since we don't know what the agent might name them, we query metadata.
    
    cursor.execute("""
        SELECT policy_name 
        FROM dba_redaction_policies 
        WHERE object_owner = 'HR' AND object_name = 'EMPLOYEES'
    """)
    policies = [row[0] for row in cursor.fetchall()]
    
    for policy in policies:
        print(f"Dropping policy: {policy}")
        try:
            cursor.execute(f"BEGIN DBMS_REDACT.DROP_POLICY(object_schema=>'HR', object_name=>'EMPLOYEES', policy_name=>'{policy}'); END;")
        except Exception as e:
            print(f"Error dropping policy {policy}: {e}")

    conn.commit()
    conn.close()
    print("Cleanup complete.")

except Exception as e:
    print(f"Setup script error: {e}")
    # Don't fail hard on cleanup errors, just warn
PYEOF

# --- Initial Screenshot ---
echo "[4/4] Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="