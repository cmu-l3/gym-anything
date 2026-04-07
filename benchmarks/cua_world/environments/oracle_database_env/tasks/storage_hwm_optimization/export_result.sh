#!/bin/bash
# Export script for Storage HWM Optimization task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Results ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Database State using Python for reliability
python3 << 'PYEOF'
import oracledb
import json
import os

result = {
    "table_exists": False,
    "row_count": 0,
    "current_size_bytes": 0,
    "current_size_mb": 0.0,
    "index_status": "UNKNOWN",
    "index_size_bytes": 0,
    "data_integrity_passed": False,
    "integrity_check_details": "",
    "db_error": None
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Check Table Existence and Size
    cursor.execute("""
        SELECT bytes 
        FROM user_segments 
        WHERE segment_name = 'SHIPMENT_LOGS'
    """)
    row = cursor.fetchone()
    if row:
        result["table_exists"] = True
        result["current_size_bytes"] = row[0]
        result["current_size_mb"] = row[0] / (1024 * 1024)

    # Check Row Count
    cursor.execute("SELECT COUNT(*) FROM shipment_logs")
    result["row_count"] = cursor.fetchone()[0]

    # Check Index Status
    cursor.execute("""
        SELECT status 
        FROM user_indexes 
        WHERE index_name = 'IDX_SHIP_LOG_DATE'
    """)
    idx_row = cursor.fetchone()
    if idx_row:
        result["index_status"] = idx_row[0]
    else:
        result["index_status"] = "MISSING"

    # Check Index Size (optional bonus info)
    cursor.execute("""
        SELECT bytes 
        FROM user_segments 
        WHERE segment_name = 'IDX_SHIP_LOG_DATE'
    """)
    idx_size_row = cursor.fetchone()
    if idx_size_row:
        result["index_size_bytes"] = idx_size_row[0]

    # DATA INTEGRITY CHECK
    # We load expected IDs from setup
    expected_ids = []
    if os.path.exists('/tmp/integrity_ids.txt'):
        with open('/tmp/integrity_ids.txt', 'r') as f:
            for line in f:
                if line.strip().isdigit():
                    expected_ids.append(int(line.strip()))
    
    # Verify these specific IDs still exist
    if expected_ids:
        id_str = ",".join(map(str, expected_ids))
        cursor.execute(f"SELECT log_id FROM shipment_logs WHERE log_id IN ({id_str})")
        found_ids = {r[0] for r in cursor.fetchall()}
        
        missing = set(expected_ids) - found_ids
        if not missing and len(found_ids) == len(expected_ids):
            result["data_integrity_passed"] = True
        else:
            result["data_integrity_passed"] = False
            result["integrity_check_details"] = f"Missing IDs: {list(missing)[:5]}..."
    else:
        # Fallback if file missing
        result["data_integrity_passed"] = (result["row_count"] == 5000)

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# 3. Add timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Append timing to JSON (using simple sed/jq/python)
python3 -c "
import json
with open('/tmp/task_result.json', 'r+') as f:
    data = json.load(f)
    data['task_start'] = $TASK_START
    data['task_end'] = $TASK_END
    f.seek(0)
    json.dump(data, f, indent=2)
    f.truncate()
"

echo "Export complete."
cat /tmp/task_result.json