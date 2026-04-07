#!/bin/bash
# Setup for redo_log_sizing_optimization task
# Forces the database into a state with 3 undersized (50MB) redo log groups.

set -e

echo "=== Setting up Redo Log Sizing Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# --- Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Wait for DB to be open ---
echo "[2/4] Waiting for database connection..."
wait_for_oracle_connection() {
    for i in {1..30}; do
        if echo "SELECT 1 FROM DUAL;" | oracle_query_raw "SELECT 1 FROM DUAL;" "system" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

if ! wait_for_oracle_connection; then
    echo "ERROR: Could not connect to database"
    exit 1
fi

# --- Reconfigure Redo Logs to Start State (3x 50MB) ---
echo "[3/4] Configuring initial state (3 groups of 50MB)..."

# Python script to handle the complex logic of swapping log groups
python3 << 'PYEOF'
import oracledb
import time
import sys

# Connect as SYSDBA equivalent (System with privileges usually suffices for XE setup, 
# or we use the specific connection string)
try:
    conn = oracledb.connect(user="system", password="OraclePassword123", dsn="localhost:1521/XEPDB1", mode=oracledb.SYSDBA)
except:
    # Fallback to standard connection if SYSDBA fails remote
    conn = oracledb.connect(user="system", password="OraclePassword123", dsn="localhost:1521/XEPDB1")

cursor = conn.cursor()

def get_log_info():
    cursor.execute("SELECT group#, bytes, status FROM v$log")
    return cursor.fetchall()

def switch_and_checkpoint():
    print("  Switching logfile...")
    cursor.execute("ALTER SYSTEM SWITCH LOGFILE")
    print("  Checkpointing...")
    cursor.execute("ALTER SYSTEM CHECKPOINT")
    time.sleep(2)

print("Current log configuration:")
logs = get_log_info()
for log in logs:
    print(f"  Group {log[0]}: {log[1]} bytes, {log[2]}")

# Check if we already have the desired state (3 groups of 50MB approx)
# 50MB = 52428800 bytes
desired_size = 52428800
is_setup = len(logs) == 3 and all(log[1] == desired_size for log in logs)

if is_setup:
    print("State already correct.")
    sys.exit(0)

print("Reconfiguring logs to 3x 50MB...")

# 1. Add 3 new small groups (groups 10, 11, 12 to avoid collision)
# Note: Oracle XE limits max log files, but usually allows a few more.
existing_groups = [log[0] for log in logs]
temp_groups = [10, 11, 12]

# Filter out if temp groups happen to exist
temp_groups = [g for g in temp_groups if g not in existing_groups]

if len(temp_groups) < 3:
    # If we can't find 3 IDs, just pick ones not in use
    all_possible = range(1, 20)
    temp_groups = [g for g in all_possible if g not in existing_groups][:3]

print(f"Creating temporary groups: {temp_groups}")
for g in temp_groups:
    try:
        cursor.execute(f"ALTER DATABASE ADD LOGFILE GROUP {g} SIZE 50M")
        print(f"  Created Group {g}")
    except oracledb.DatabaseError as e:
        print(f"  Error creating group {g}: {e}")

# 2. Switch logs until a new small group is CURRENT
print("Cycling logs to make new groups active...")
max_switches = 10
for _ in range(max_switches):
    cursor.execute("SELECT group# FROM v$log WHERE status='CURRENT'")
    current = cursor.fetchone()[0]
    if current in temp_groups:
        break
    switch_and_checkpoint()

# 3. Drop old groups
print("Dropping original groups...")
logs = get_log_info()
for log in logs:
    grp = log[0]
    if grp not in temp_groups:
        # Loop to ensure it's not active
        retries = 0
        while retries < 5:
            cursor.execute(f"SELECT status FROM v$log WHERE group#={grp}")
            status = cursor.fetchone()[0]
            if status == 'CURRENT':
                switch_and_checkpoint()
            elif status == 'ACTIVE':
                cursor.execute("ALTER SYSTEM CHECKPOINT")
                time.sleep(2)
            else:
                try:
                    cursor.execute(f"ALTER DATABASE DROP LOGFILE GROUP {grp}")
                    print(f"  Dropped Group {grp}")
                    # Try to delete file from disk? (Optional, Oracle keeps file open sometimes)
                    break
                except Exception as e:
                    print(f"  Retry dropping {grp}: {e}")
            retries += 1
            time.sleep(1)

# 4. Normalize group numbers? 
# Not strictly necessary, but we leave the agent with groups 10, 11, 12 (or whatever).
# The task requires them to create NEW groups (e.g. 4, 5, 6) and drop these.

# Verify final state
logs = get_log_info()
print("Final Setup State:")
count = 0
for log in logs:
    print(f"  Group {log[0]}: {log[1]} bytes")
    count += 1

if count != 3:
    print(f"WARNING: Ended up with {count} groups instead of 3")

PYEOF

# --- Record Initial State for Verification ---
echo "[4/4] Recording initial state..."
python3 << 'PYEOF'
import oracledb
import json

try:
    conn = oracledb.connect(user="system", password="OraclePassword123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()
    cursor.execute("SELECT group#, bytes FROM v$log")
    rows = cursor.fetchall()
    
    data = {
        "initial_groups": [{"group": r[0], "bytes": r[1]} for r in rows],
        "count": len(rows)
    }
    
    with open("/tmp/initial_redo_state.json", "w") as f:
        json.dump(data, f)
except Exception as e:
    print(f"Error saving state: {e}")
PYEOF

chmod 644 /tmp/initial_redo_state.json

# Ensure DBeaver is ready (but not open, let agent open it)
echo "=== Setup Complete ==="