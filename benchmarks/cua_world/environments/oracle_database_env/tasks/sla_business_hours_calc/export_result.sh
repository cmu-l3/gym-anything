#!/bin/bash
# Export results for SLA Business Hours Calculation
# Queries the user's view and checks the CSV export

set -e

echo "=== Exporting SLA Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Path to python script for robust DB querying
EXPORT_PY="/tmp/export_sla_results.py"

cat > "$EXPORT_PY" << 'PYEOF'
import oracledb
import json
import os
import csv
import datetime

result = {
    "view_exists": False,
    "columns_correct": False,
    "trap_data": {},
    "csv_exists": False,
    "csv_valid": False,
    "csv_rows": 0,
    "db_error": None
}

try:
    # Connect to DB
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check View Existence
    cursor.execute("SELECT COUNT(*) FROM user_views WHERE view_name = 'SLA_PERFORMANCE_VW'")
    if cursor.fetchone()[0] > 0:
        result["view_exists"] = True
        
        # 2. Check Columns
        cursor.execute("SELECT column_name FROM user_tab_cols WHERE table_name = 'SLA_PERFORMANCE_VW'")
        cols = set([row[0].upper() for row in cursor.fetchall()])
        required = {'TICKET_ID', 'PRIORITY', 'OPENED_AT', 'CLOSED_AT', 'TOTAL_HOURS', 'BUSINESS_MINUTES', 'SLA_STATUS'}
        result["columns_correct"] = required.issubset(cols)
        result["found_columns"] = list(cols)

        # 3. Query Trap Data from View
        # We query specific IDs to see if the agent's logic matches our expectations
        trap_ids = [1001, 1002, 1003, 1004]
        
        for tid in trap_ids:
            try:
                cursor.execute(f"SELECT business_minutes, sla_status FROM sla_performance_vw WHERE ticket_id = {tid}")
                row = cursor.fetchone()
                if row:
                    result["trap_data"][str(tid)] = {
                        "minutes": float(row[0]) if row[0] is not None else -1,
                        "status": row[1]
                    }
            except Exception as e:
                result["trap_data"][str(tid)] = {"error": str(e)}

    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# 4. Check CSV Export
csv_path = "/home/ga/Desktop/sla_report.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    try:
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            rows = list(reader)
            if len(rows) > 1: # Header + Data
                result["csv_valid"] = True
                result["csv_rows"] = len(rows) - 1 # exclude header
    except Exception as e:
        result["csv_valid"] = False

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Run the python export script
python3 "$EXPORT_PY"

echo "Export complete. JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json