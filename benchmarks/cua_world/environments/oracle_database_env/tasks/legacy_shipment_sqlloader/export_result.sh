#!/bin/bash
# Export results for Legacy Shipment SQL*Loader task

set -e

echo "=== Exporting SQL*Loader Task Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Load expected values
EXPECTED_JSON=$(cat /tmp/expected_shipment_data.json)
EXP_VALID_COUNT=$(echo "$EXPECTED_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['valid_count'])")
EXP_COST_SUM=$(echo "$EXPECTED_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['total_valid_cost'])")

# Run export script
python3 << PYEOF
import oracledb
import json
import os
import datetime

result = {
    "table_exists": False,
    "row_count": 0,
    "cost_sum": 0.0,
    "void_count_in_db": 0,
    "columns": [],
    "column_types": {},
    "control_file_exists": False,
    "control_file_content": "",
    "export_timestamp": datetime.datetime.now().isoformat(),
    "db_error": None
}

# 1. Check DB State
try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()
    
    # Check table existence
    cursor.execute("SELECT count(*) FROM user_tables WHERE table_name = 'SHIPMENT_HISTORY'")
    if cursor.fetchone()[0] > 0:
        result["table_exists"] = True
        
        # Get columns and types
        cursor.execute("SELECT column_name, data_type FROM user_tab_columns WHERE table_name = 'SHIPMENT_HISTORY'")
        for row in cursor.fetchall():
            result["columns"].append(row[0])
            result["column_types"][row[0]] = row[1]
            
        # Get Row Count
        cursor.execute("SELECT count(*) FROM shipment_history")
        result["row_count"] = cursor.fetchone()[0]
        
        # Get Cost Sum
        cursor.execute("SELECT NVL(SUM(cost), 0) FROM shipment_history")
        result["cost_sum"] = float(cursor.fetchone()[0])
        
        # Check for Voids (should be 0 if filtered correctly)
        # We look for a status column if it exists, otherwise we might check IDs
        # Assuming user named column STATUS or STATUS_CODE based on task description
        status_col = next((c for c in result["columns"] if "STATUS" in c), None)
        if status_col:
            cursor.execute(f"SELECT count(*) FROM shipment_history WHERE {status_col} = '99'")
            result["void_count_in_db"] = cursor.fetchone()[0]

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# 2. Check Control File Artifact
ctl_path = "/home/ga/Desktop/load_shipments.ctl"
if os.path.exists(ctl_path):
    result["control_file_exists"] = True
    try:
        with open(ctl_path, "r") as f:
            result["control_file_content"] = f.read(2000) # Read first 2KB
    except:
        pass

# 3. Add expected values for verifier
result["expected_row_count"] = $EXP_VALID_COUNT
result["expected_cost_sum"] = $EXP_COST_SUM

with open("/tmp/sqlloader_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result exported to /tmp/sqlloader_result.json")
PYEOF

echo "=== Export Complete ==="