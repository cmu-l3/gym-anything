#!/bin/bash
# Export script for merge_error_logging task
# Exports DB state and checks for file artifacts

echo "=== Exporting Merge Error Logging Results ==="

source /workspace/scripts/task_utils.sh

# Take screenshot
take_screenshot /tmp/task_end_screenshot.png

# Run Python script to gather detailed verification data
python3 << 'PYEOF'
import oracledb
import json
import os
import csv

result = {
    "error_table_exists": False,
    "employees_count": 0,
    "error_log_count": 0,
    "valid_update_100_check": False,
    "valid_update_103_check": False,
    "valid_insert_301_exists": False,
    "invalid_insert_303_exists": False,
    "error_types_found": [],
    "report_file_exists": False,
    "report_file_lines": 0
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Error Table Existence
    cursor.execute("SELECT count(*) FROM user_tables WHERE table_name = 'ERR_EMPLOYEES_LOG'")
    if cursor.fetchone()[0] > 0:
        result["error_table_exists"] = True
        
        # 2. Check Error Log Content
        cursor.execute("SELECT COUNT(*) FROM err_employees_log")
        result["error_log_count"] = cursor.fetchone()[0]
        
        # Check specific error messages to ensure they aren't generic garbage
        cursor.execute("SELECT ora_err_mesg$ FROM err_employees_log")
        errors = [r[0] for r in cursor.fetchall()]
        result["error_types_found"] = errors

    # 3. Check Employees Table State (Target)
    cursor.execute("SELECT COUNT(*) FROM employees")
    result["employees_count"] = cursor.fetchone()[0]

    # 4. Check Valid Updates
    # Emp 100 should now have salary 25000 (was 24000)
    cursor.execute("SELECT salary FROM employees WHERE employee_id = 100")
    row = cursor.fetchone()
    if row and row[0] == 25000:
        result["valid_update_100_check"] = True
        
    # Emp 103 should have salary 9500 (was 9000)
    cursor.execute("SELECT salary FROM employees WHERE employee_id = 103")
    row = cursor.fetchone()
    if row and row[0] == 9500:
        result["valid_update_103_check"] = True

    # 5. Check Valid Inserts
    # Emp 301 should exist
    cursor.execute("SELECT count(*) FROM employees WHERE employee_id = 301")
    if cursor.fetchone()[0] > 0:
        result["valid_insert_301_exists"] = True

    # 6. Check Invalid Inserts (Should NOT exist)
    # Emp 303 (Bad Job) should not exist
    cursor.execute("SELECT count(*) FROM employees WHERE employee_id = 303")
    if cursor.fetchone()[0] > 0:
        result["invalid_insert_303_exists"] = True

    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# 7. Check Report File
report_path = "/home/ga/Desktop/sync_errors.csv"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    try:
        with open(report_path, 'r') as f:
            result["report_file_lines"] = len(f.readlines())
    except:
        pass

# Save to JSON
with open("/tmp/merge_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

cat /tmp/merge_result.json
echo "=== Export Complete ==="