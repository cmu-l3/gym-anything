#!/bin/bash
# Setup for JSON Relational Duality View task
# Ensures clean state by removing the target view and specific data rows if they exist.

set -e

echo "=== Setting up JSON Duality View Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container ($ORACLE_CONTAINER) not running!"
    exit 1
fi

# --- Pre-flight: Wait for DB and HR schema ---
echo "[2/4] Verifying HR schema connectivity..."
for attempt in {1..10}; do
    if oracle_query_raw "SELECT 1 FROM DUAL;" "hr" >/dev/null 2>&1; then
        echo "  Database ready."
        break
    fi
    echo "  Waiting for database... ($attempt/10)"
    sleep 5
done

# --- Cleanup: Remove artifacts from previous runs ---
echo "[3/4] Cleaning up prior task artifacts..."
# We use a Python script to handle the cleanup robustly via oracledb
python3 << 'PYEOF'
import oracledb
import sys

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()
    
    # 1. Drop the duality view if it exists
    try:
        cursor.execute("DROP VIEW DEPT_EMP_DV")
        print("  Dropped existing view DEPT_EMP_DV")
    except oracledb.DatabaseError as e:
        if "ORA-00942" not in str(e): # table or view does not exist
            print(f"  Warning dropping view: {e}")

    # 2. Delete the specific employee records (children first)
    cursor.execute("DELETE FROM employees WHERE employee_id IN (3001, 3002)")
    print(f"  Deleted {cursor.rowcount} employees (3001, 3002)")

    # 3. Delete the specific department record
    cursor.execute("DELETE FROM departments WHERE department_id = 300")
    print(f"  Deleted {cursor.rowcount} department (300)")

    conn.commit()
    cursor.close()
    conn.close()
except Exception as e:
    print(f"ERROR during cleanup: {e}")
    sys.exit(1)
PYEOF

# Clean up local file
rm -f /home/ga/Desktop/cloud_ops.json

# --- Record Start Time ---
echo "[4/4] Recording start time..."
date +%s > /tmp/task_start_timestamp
chmod 644 /tmp/task_start_timestamp

# Ensure DBeaver is not running to give a clean start
pkill -f dbeaver 2>/dev/null || true

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "  Target Dept 300 and Emps 3001/3002 cleared."
echo "  View DEPT_EMP_DV dropped."