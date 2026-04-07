#!/bin/bash
# Setup for Storage Emergency Response task
# Creates a full tablespace scenario to simulate ORA-01653

set -e

echo "=== Setting up Storage Emergency Response Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "[1/5] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Create Tablespace and Data ---
echo "[2/5] Creating tablespaces and populating data..."

# We use a python script to handle the loop insert logic gracefully
python3 << 'PYEOF'
import oracledb
import sys
import time

try:
    # Connect as SYSTEM
    conn = oracledb.connect(user="system", password="OraclePassword123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    print("  Connected to database.")

    # 1. Clean up potential leftovers
    try:
        cursor.execute("DROP TABLE emr_admission_logs PURGE")
    except: pass
    try:
        cursor.execute("DROP TABLE emr_historical_logs PURGE")
    except: pass
    try:
        cursor.execute("DROP TABLESPACE ts_archive INCLUDING CONTENTS AND DATAFILES")
    except: pass
    try:
        cursor.execute("DROP TABLESPACE ts_emr_logs INCLUDING CONTENTS AND DATAFILES")
    except: pass

    # 2. Create small fixed-size tablespace (20MB)
    print("  Creating TS_EMR_LOGS (20MB)...")
    cursor.execute("""
        CREATE TABLESPACE ts_emr_logs 
        DATAFILE 'ts_emr_logs.dbf' SIZE 20M 
        AUTOEXTEND OFF
        EXTENT MANAGEMENT LOCAL UNIFORM SIZE 128K
    """)

    # 3. Create tables
    print("  Creating tables...")
    cursor.execute("""
        CREATE TABLE emr_historical_logs (
            log_id NUMBER GENERATED ALWAYS AS IDENTITY,
            patient_id NUMBER,
            log_date DATE,
            log_data VARCHAR2(4000)
        ) TABLESPACE ts_emr_logs
    """)
    
    cursor.execute("""
        CREATE TABLE emr_admission_logs (
            admission_id NUMBER GENERATED ALWAYS AS IDENTITY,
            patient_id NUMBER,
            admission_date DATE,
            notes VARCHAR2(4000)
        ) TABLESPACE ts_emr_logs
    """)

    # 4. Create index on historical logs (to test rebuild requirement later)
    cursor.execute("""
        CREATE INDEX idx_hist_patient ON emr_historical_logs(patient_id) 
        TABLESPACE ts_emr_logs
    """)

    # 5. Fill ~75% with Historical Data
    print("  Populating Historical Data...")
    # Insert large chunks of data
    large_text = "X" * 3500
    for i in range(1500): # Adjust count to fill ~15MB
        try:
            cursor.execute(f"INSERT INTO emr_historical_logs (patient_id, log_date, log_data) VALUES ({i}, SYSDATE - 365, :1)", [large_text])
        except oracledb.DatabaseError as e:
            print(f"  Warning: Hit limit early during history load: {e}")
            break
    conn.commit()

    # 6. Fill the rest with Admission Data until failure
    print("  Filling remaining space with Admission Data until ORA-01653...")
    rows_inserted = 0
    try:
        while True:
            cursor.execute(f"INSERT INTO emr_admission_logs (patient_id, admission_date, notes) VALUES (1001, SYSDATE, :1)", [large_text])
            rows_inserted += 1
            if rows_inserted % 100 == 0:
                conn.commit() # Commit periodically
    except oracledb.DatabaseError as e:
        error_obj = e.args[0]
        if "ORA-01653" in error_obj.message:
            print("  SUCCESS: Tablespace full state achieved (ORA-01653).")
        else:
            print(f"  UNEXPECTED ERROR: {error_obj.message}")
            # If we hit another error, we might not be full, but for the sake of setup, 
            # let's try one more commit
            pass
    
    conn.commit()
    
    # Verify we really can't insert
    try:
        cursor.execute("INSERT INTO emr_admission_logs (patient_id, admission_date, notes) VALUES (9999, SYSDATE, 'test')")
        print("  WARNING: Still able to insert? Setup might be flaky.")
    except oracledb.DatabaseError as e:
        print("  Verified: Cannot insert new records.")

    cursor.close()
    conn.close()

except Exception as e:
    print(f"PYTHON SCRIPT ERROR: {e}")
    sys.exit(1)
PYEOF

# --- Record Task Start Time ---
echo "[3/5] Recording start time..."
date +%s > /tmp/task_start_timestamp

# --- Ensure DBeaver/SQL Developer is ready ---
echo "[4/5] Checking DBeaver..."
if ! which dbeaver-ce > /dev/null 2>&1; then
    echo "Installing DBeaver..."
    sudo snap install dbeaver-ce --classic 2>/dev/null || true
fi

# --- Take Snapshot ---
echo "[5/5] Taking initial screenshot..."
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "System is now in a critical state: TS_EMR_LOGS is full."