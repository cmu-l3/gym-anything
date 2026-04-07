#!/bin/bash
# Setup script for RBAC Security Implementation task
# Ensures a clean state by dropping target roles, users, and views if they exist

set -e

echo "=== Setting up RBAC Security Task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# --- Pre-flight: Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Pre-flight: Verify Connectivity ---
echo "[2/4] Verifying database connectivity..."
wait_for_oracle_ready() {
    for i in {1..30}; do
        if oracle_query_raw "SELECT 1 FROM DUAL;" "system" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

if ! wait_for_oracle_ready; then
    echo "ERROR: Database not ready."
    exit 1
fi

# --- Clean Clean Slate ---
echo "[3/4] Cleaning up previous attempts..."
# We use a python script to handle the cleanup logic robustly (ignoring errors if objects don't exist)
python3 << 'PYEOF'
import oracledb
import sys

try:
    conn = oracledb.connect(user="system", password="OraclePassword123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    def drop_user(username):
        try:
            cursor.execute(f"DROP USER {username} CASCADE")
            print(f"Dropped user {username}")
        except oracledb.DatabaseError:
            pass # Ignore if doesn't exist

    def drop_role(rolename):
        try:
            cursor.execute(f"DROP ROLE {rolename}")
            print(f"Dropped role {rolename}")
        except oracledb.DatabaseError:
            pass

    # Drop Users
    drop_user("APP_READER")
    drop_user("APP_ANALYST")
    drop_user("APP_MANAGER")

    # Drop Roles
    drop_role("HR_READONLY")
    drop_role("HR_ANALYST")
    drop_role("HR_MANAGER")

    conn.close()

    # Drop Views as HR
    conn_hr = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor_hr = conn_hr.cursor()
    
    def drop_view(viewname):
        try:
            cursor_hr.execute(f"DROP VIEW {viewname}")
            print(f"Dropped view {viewname}")
        except oracledb.DatabaseError:
            pass

    drop_view("V_EMPLOYEE_PUBLIC")
    drop_view("V_DEPT_SUMMARY")
    
    conn_hr.close()

except Exception as e:
    print(f"Cleanup warning: {e}")
PYEOF

# Remove report file
rm -f /home/ga/Desktop/security_report.txt

# --- Capture Initial State ---
echo "[4/4] capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="
echo "Users, roles, and views have been reset."