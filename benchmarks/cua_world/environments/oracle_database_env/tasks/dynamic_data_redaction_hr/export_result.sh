#!/bin/bash
# Export results for Dynamic Data Redaction Task
# Verifies the implementation by querying as both users

set -e

echo "=== Exporting Redaction Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run verification logic in Python inside the container environment
# We use Python because it's easier to handle multiple connections and structured output
python3 << 'PYEOF'
import oracledb
import json
import os
import datetime

# Output structure
result = {
    "qa_user_exists": False,
    "policies_exist": False,
    "policy_names": [],
    "redaction_columns": [],
    "qa_view": {
        "salary": None,
        "commission": None,
        "phone": None,
        "email": None
    },
    "hr_view": {
        "salary": None,
        "commission": None,
        "phone": None,
        "email": None
    },
    "errors": []
}

dsn = "localhost:1521/XEPDB1"

# 1. Check Metadata (as SYSTEM)
try:
    conn_sys = oracledb.connect(user="system", password="OraclePassword123", dsn=dsn)
    cursor_sys = conn_sys.cursor()
    
    # Check if user exists
    cursor_sys.execute("SELECT username FROM dba_users WHERE username = 'QA_TESTER'")
    if cursor_sys.fetchone():
        result["qa_user_exists"] = True

    # Check policies
    cursor_sys.execute("""
        SELECT policy_name, expression
        FROM dba_redaction_policies 
        WHERE object_owner = 'HR' AND object_name = 'EMPLOYEES'
    """)
    rows = cursor_sys.fetchall()
    if rows:
        result["policies_exist"] = True
        result["policy_names"] = [r[0] for r in rows]
        result["policy_expressions"] = [str(r[1]) for r in rows]

    # Check columns
    cursor_sys.execute("""
        SELECT column_name, function_type
        FROM dba_redaction_columns
        WHERE object_owner = 'HR' AND object_name = 'EMPLOYEES'
    """)
    cols = cursor_sys.fetchall()
    result["redaction_columns"] = [{"name": r[0], "type": r[1]} for r in cols]

    conn_sys.close()
except Exception as e:
    result["errors"].append(f"System check error: {str(e)}")

# 2. Check Data as QA_TESTER
if result["qa_user_exists"]:
    try:
        # Connect as QA_TESTER
        conn_qa = oracledb.connect(user="QA_TESTER", password="QaUser#2024", dsn=dsn)
        cursor_qa = conn_qa.cursor()
        
        # Query sample row (Employee 100 - Steven King)
        # Assuming sample data: Sal=24000, Comm=NULL(or 0.X), Phone=515.123.4567, Email=SKING
        cursor_qa.execute("""
            SELECT salary, commission_pct, phone_number, email 
            FROM hr.employees 
            WHERE employee_id = 100
        """)
        row = cursor_qa.fetchone()
        if row:
            result["qa_view"] = {
                "salary": row[0],
                "commission": row[1],
                "phone": row[2],
                "email": row[3]
            }
        
        conn_qa.close()
    except Exception as e:
        result["errors"].append(f"QA_TESTER query error: {str(e)}")

# 3. Check Data as HR (Owner) - Should be unredacted
try:
    conn_hr = oracledb.connect(user="hr", password="hr123", dsn=dsn)
    cursor_hr = conn_hr.cursor()
    
    cursor_hr.execute("""
        SELECT salary, commission_pct, phone_number, email 
        FROM employees 
        WHERE employee_id = 100
    """)
    row = cursor_hr.fetchone()
    if row:
        result["hr_view"] = {
            "salary": row[0],
            "commission": row[1],
            "phone": row[2],
            "email": row[3]
        }
    
    conn_hr.close()
except Exception as e:
    result["errors"].append(f"HR query error: {str(e)}")

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

PYEOF

echo "Export complete. Result:"
cat /tmp/task_result.json