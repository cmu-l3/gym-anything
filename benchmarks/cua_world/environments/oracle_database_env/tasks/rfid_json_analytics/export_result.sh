#!/bin/bash
# Export script for RFID JSON Analytics task

set -e
echo "=== Exporting RFID Analytics Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to interact with Oracle and create the result JSON
python3 << 'PYEOF'
import oracledb
import json
import os
import datetime

result = {
    "views": {},
    "function": {},
    "file": {},
    "data_checks": {},
    "timestamp": datetime.datetime.now().isoformat()
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # --- 1. Check Views Existence and Columns ---
    views_to_check = ["RFID_EVENTS_FLAT", "ZONE_TRAFFIC_SUMMARY"]
    for view in views_to_check:
        try:
            # Check existence
            cursor.execute("SELECT count(*) FROM user_views WHERE view_name = :1", [view])
            exists = cursor.fetchone()[0] > 0
            
            columns = []
            row_count = 0
            sample_data = {}
            
            if exists:
                # Get columns
                cursor.execute("SELECT column_name FROM user_tab_columns WHERE table_name = :1", [view])
                columns = [r[0] for r in cursor.fetchall()]
                
                # Get row count
                cursor.execute(f"SELECT count(*) FROM {view}")
                row_count = cursor.fetchone()[0]
                
                # Get sample row
                if row_count > 0:
                    cursor.execute(f"SELECT * FROM {view} FETCH FIRST 1 ROWS ONLY")
                    # Simple fetch, we just want to know it works
                    sample_data = "fetched_ok"

            result["views"][view] = {
                "exists": exists,
                "columns": columns,
                "row_count": row_count,
                "queryable": True if sample_data else False
            }
        except Exception as e:
            result["views"][view] = {"exists": False, "error": str(e)}

    # --- 2. Check Function Existence and Logic ---
    func_name = "GET_TAG_HISTORY"
    try:
        cursor.execute("SELECT status FROM user_objects WHERE object_name = :1 AND object_type = 'FUNCTION'", [func_name])
        row = cursor.fetchone()
        func_exists = True if row else False
        func_status = row[0] if row else "MISSING"
        
        func_output = ""
        func_error_handling = ""
        
        if func_status == "VALID":
            # Test with a known tag (we grab one from base table)
            cursor.execute("SELECT JSON_VALUE(event_data, '$.tag_id') FROM rfid_events FETCH FIRST 1 ROWS ONLY")
            tag_id = cursor.fetchone()[0]
            
            # Call function
            cursor.execute(f"SELECT {func_name}(:1) FROM DUAL", [tag_id])
            func_output = cursor.fetchone()[0]
            
            # Test error handling
            cursor.execute(f"SELECT {func_name}('NON_EXISTENT_TAG') FROM DUAL")
            func_error_handling = cursor.fetchone()[0]

        result["function"] = {
            "exists": func_exists,
            "status": func_status,
            "test_output": str(func_output),
            "error_handling_output": str(func_error_handling)
        }
    except Exception as e:
        result["function"] = {"exists": False, "error": str(e)}

    # --- 3. Validate Specific Logic in Views ---
    # Check if summary view actually aggregates (count < base table count)
    if result["views"]["ZONE_TRAFFIC_SUMMARY"].get("exists"):
        try:
            cursor.execute("SELECT SUM(total_reads) FROM zone_traffic_summary")
            sum_reads = cursor.fetchone()[0]
            cursor.execute("SELECT count(*) FROM rfid_events")
            total_events = cursor.fetchone()[0]
            result["data_checks"]["sum_matches_total"] = (sum_reads == total_events)
        except:
            result["data_checks"]["sum_matches_total"] = False

except Exception as e:
    result["error"] = str(e)
finally:
    try:
        conn.close()
    except:
        pass

# --- 4. Check Export File ---
file_path = "/home/ga/Desktop/warehouse_report.txt"
if os.path.exists(file_path):
    result["file"]["exists"] = True
    result["file"]["size"] = os.path.getsize(file_path)
    # Read first few lines
    try:
        with open(file_path, 'r') as f:
            result["file"]["content_head"] = f.read(200)
    except:
        pass
    # Check creation time vs task start
    mtime = os.path.getmtime(file_path)
    task_start = int(os.environ.get("TASK_START", 0))
    result["file"]["created_during_task"] = (mtime > task_start)
else:
    result["file"]["exists"] = False

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json