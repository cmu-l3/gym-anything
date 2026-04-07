#!/bin/bash
# Export results for JSON Duality View task
# Queries database metadata and content to verify the task was performed correctly.

set -e

echo "=== Exporting JSON Duality View Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/json_duality_final_screenshot.png

echo "Gathering verification data..."

# Use Python for reliable structured data export
python3 << 'PYEOF'
import oracledb
import json
import os
import datetime

result = {
    "view_exists": False,
    "view_status": "MISSING",
    "view_text": "",
    "dept_300_exists": False,
    "dept_300_name": None,
    "emp_3001_exists": False,
    "emp_3001_email": None,
    "emp_3002_exists": False,
    "file_exists": False,
    "file_content_valid": False,
    "file_json": None,
    "timestamp": datetime.datetime.now().isoformat()
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check View Existence and Status
    print("Checking view status...")
    cursor.execute("""
        SELECT status 
        FROM user_objects 
        WHERE object_name = 'DEPT_EMP_DV' AND object_type = 'VIEW'
    """)
    row = cursor.fetchone()
    if row:
        result["view_exists"] = True
        result["view_status"] = row[0]

    # 2. Get View Definition (to ensure it's a JSON duality view)
    # Using DBMS_METADATA usually, but let's check user_json_duality_views if available in 21c
    # Fallback to checking user_views text for "JSON"
    if result["view_exists"]:
        try:
            cursor.execute("""
                SELECT text 
                FROM user_views 
                WHERE view_name = 'DEPT_EMP_DV'
            """)
            row = cursor.fetchone()
            if row:
                # text is a LOB, read it
                result["view_text"] = str(row[0])
        except Exception as e:
            result["view_text_error"] = str(e)
            
        # Check specific metadata for duality views if possible
        try:
            cursor.execute("""
                SELECT count(*) FROM user_json_duality_views WHERE view_name = 'DEPT_EMP_DV'
            """)
            if cursor.fetchone()[0] > 0:
                result["is_duality_view"] = True
        except:
            pass

    # 3. Check Relational Data (Ground Truth)
    # The agent should have inserted data via the view, which populates tables.
    print("Checking relational data...")
    
    # Check Department
    cursor.execute("SELECT department_name FROM departments WHERE department_id = 300")
    row = cursor.fetchone()
    if row:
        result["dept_300_exists"] = True
        result["dept_300_name"] = row[0]

    # Check Employees
    cursor.execute("SELECT email, first_name, last_name FROM employees WHERE employee_id = 3001")
    row = cursor.fetchone()
    if row:
        result["emp_3001_exists"] = True
        result["emp_3001_email"] = row[0]

    cursor.execute("SELECT email FROM employees WHERE employee_id = 3002")
    row = cursor.fetchone()
    if row:
        result["emp_3002_exists"] = True

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)
    print(f"DB Error: {e}")

# 4. Check Exported File
print("Checking exported file...")
file_path = "/home/ga/Desktop/cloud_ops.json"
if os.path.exists(file_path):
    result["file_exists"] = True
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
            result["file_json"] = data
            result["file_content_valid"] = True
            
            # Simple validation of file content
            if data.get("deptId") == 300:
                result["file_matches_id"] = True
    except Exception as e:
        result["file_error"] = str(e)

# Save result
with open("/tmp/json_duality_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Fix permissions
chmod 644 /tmp/json_duality_result.json 2>/dev/null || true

echo "=== Export Complete ==="