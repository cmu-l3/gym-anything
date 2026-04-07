#!/bin/bash
# Setup script for Storage HWM Optimization task
# Creates a fragmented table by inserting large data and deleting 90% of it without resetting HWM.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Storage HWM Optimization Task ==="

# 1. Verify Oracle is ready
echo "Checking database availability..."
wait_for_oracle_ready() {
    for i in {1..30}; do
        if sudo docker exec oracle-xe bash -c "sqlplus -s hr/hr123@localhost:1521/XEPDB1 <<'SQLEOF'
SELECT 1 FROM DUAL;
EXIT;
SQLEOF" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

if ! wait_for_oracle_ready; then
    echo "ERROR: Oracle database not reachable."
    exit 1
fi

# 2. Create and Fragment the Table
# We insert 50,000 rows with 4KB payload padding, then delete 90%
echo "Creating and fragmenting SHIPMENT_LOGS table (this may take 30-60s)..."

python3 << 'PYEOF'
import oracledb
import sys
import random

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Drop if exists
    try:
        cursor.execute("DROP TABLE shipment_logs PURGE")
    except oracledb.DatabaseError:
        pass

    # Create table with large payload column to consume blocks
    print("Creating table structure...")
    cursor.execute("""
        CREATE TABLE shipment_logs (
            log_id NUMBER PRIMARY KEY,
            shipment_date DATE,
            status VARCHAR2(20),
            payload VARCHAR2(4000)
        )
    """)

    # Insert 50,000 rows
    # We use a batch insert for speed
    print("Inserting 50,000 bulky records...")
    rows = []
    padding = "X" * 3800 # Fill block quickly
    for i in range(1, 50001):
        # Every 10th row is "ACTIVE" (kept), others "ARCHIVED" (to be deleted)
        status = "ACTIVE" if i % 10 == 0 else "ARCHIVED" 
        rows.append((i, status, padding))
        
        if len(rows) >= 1000:
            cursor.executemany("""
                INSERT INTO shipment_logs (log_id, shipment_date, status, payload)
                VALUES (:1, SYSDATE - MOD(:1, 365), :2, :3)
            """, rows)
            rows = []
            conn.commit()
    
    if rows:
        cursor.executemany("""
            INSERT INTO shipment_logs (log_id, shipment_date, status, payload)
            VALUES (:1, SYSDATE - MOD(:1, 365), :2, :3)
        """, rows)
        conn.commit()

    # Create index (will also be large)
    print("Creating index...")
    cursor.execute("CREATE INDEX idx_ship_log_date ON shipment_logs(shipment_date)")

    # Gather stats before deletion to establish high baseline
    cursor.execute("BEGIN DBMS_STATS.GATHER_TABLE_STATS('HR', 'SHIPMENT_LOGS'); END;")

    # Check initial size
    cursor.execute("SELECT bytes/1024/1024 FROM user_segments WHERE segment_name = 'SHIPMENT_LOGS'")
    size_mb = cursor.fetchone()[0]
    print(f"Initial Table Size: {size_mb:.2f} MB")

    # DELETE 90% of rows (Status = ARCHIVED)
    # This leaves empty blocks but does NOT lower HWM
    print("Deleting 90% of records (simulating fragmentation)...")
    cursor.execute("DELETE FROM shipment_logs WHERE status = 'ARCHIVED'")
    conn.commit()

    # Count remaining
    cursor.execute("SELECT COUNT(*) FROM shipment_logs")
    count = cursor.fetchone()[0]
    print(f"Rows remaining: {count}")
    
    cursor.close()
    conn.close()

except Exception as e:
    print(f"Python Setup Error: {e}")
    sys.exit(1)
PYEOF

# 3. Capture Initial State for Verification
echo "Capturing integrity baseline..."
# Save specific IDs that MUST exist (to prevent Drop/Create cheating)
oracle_query_raw "SELECT log_id FROM shipment_logs WHERE MOD(log_id, 1000) = 0 ORDER BY log_id;" "hr" > /tmp/integrity_ids.txt
chmod 600 /tmp/integrity_ids.txt

# Save initial segment size
INITIAL_SIZE=$(oracle_query_raw "SELECT bytes FROM user_segments WHERE segment_name = 'SHIPMENT_LOGS';" "hr" | tr -d ' ')
echo "$INITIAL_SIZE" > /tmp/initial_table_bytes.txt

# 4. Start DBeaver (Agent Tool)
echo "Starting DBeaver..."
if ! pgrep -f dbeaver > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/bin/dbeaver-ce &"
    sleep 10
fi

# Maximize DBeaver
DISPLAY=:1 wmctrl -r "DBeaver" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Timestamp and Screenshot
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="