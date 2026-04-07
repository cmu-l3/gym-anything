#!/bin/bash
# Export results for FGA Privacy Compliance Audit
# Checks policy configuration and performs a functional test of the audit trigger.

set -e

echo "=== Exporting FGA Privacy Compliance Audit Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to interact with Oracle for complex validation
python3 << 'PYEOF'
import oracledb
import json
import os
import datetime
import time

result = {
    "policy_exists": False,
    "policy_details": {},
    "evidence_file_exists": False,
    "evidence_file_valid": False,
    "audit_trail_count_before_test": 0,
    "audit_trail_count_after_test": 0,
    "functional_test_passed": False,
    "test_query_error": None
}

try:
    # Connect as SYSTEM to check policies
    dsn = "localhost:1521/XEPDB1"
    conn_sys = oracledb.connect(user="system", password="OraclePassword123", dsn=dsn)
    cursor_sys = conn_sys.cursor()

    # 1. Check Policy Configuration
    print("Checking policy configuration...")
    cursor_sys.execute("""
        SELECT policy_name, policy_text, policy_column, enabled, sel, ins, upd, del
        FROM dba_audit_policies
        WHERE object_schema = 'HR' 
          AND object_name = 'EMPLOYEES' 
          AND policy_name = 'AUDIT_VIP_ACCESS'
    """)
    row = cursor_sys.fetchone()
    
    if row:
        result["policy_exists"] = True
        result["policy_details"] = {
            "name": row[0],
            "condition_text": row[1],
            "columns": row[2],
            "enabled": row[3],
            "audit_select": row[4],
            "audit_insert": row[5],
            "audit_update": row[6],
            "audit_delete": row[7]
        }
        
        # Get baseline audit count for this policy
        cursor_sys.execute("""
            SELECT COUNT(*) FROM dba_fga_audit_trail 
            WHERE policy_name = 'AUDIT_VIP_ACCESS'
        """)
        result["audit_trail_count_before_test"] = cursor_sys.fetchone()[0]
        
    cursor_sys.close()
    conn_sys.close()

    # 2. Functional Test: Run a query that SHOULD trigger the audit
    # Only run if policy exists and is enabled
    if result["policy_exists"] and result["policy_details"].get("enabled") == 'YES':
        print("Running functional test...")
        try:
            # Connect as HR (the target user)
            conn_hr = oracledb.connect(user="hr", password="hr123", dsn=dsn)
            cursor_hr = conn_hr.cursor()
            
            # Execute a query that meets criteria: Salary > 15000 AND accessing SALARY column
            # Employee 100 (Steven King) has salary 24000
            cursor_hr.execute("SELECT salary FROM employees WHERE employee_id = 100")
            cursor_hr.fetchall()
            
            cursor_hr.close()
            conn_hr.close()
            
            # Allow buffer time for audit trail to flush (Oracle FGA is usually synchronous but good to be safe)
            time.sleep(1)
            
            # Check count again as SYSTEM
            conn_sys = oracledb.connect(user="system", password="OraclePassword123", dsn=dsn)
            cursor_sys = conn_sys.cursor()
            cursor_sys.execute("""
                SELECT COUNT(*) FROM dba_fga_audit_trail 
                WHERE policy_name = 'AUDIT_VIP_ACCESS'
            """)
            result["audit_trail_count_after_test"] = cursor_sys.fetchone()[0]
            
            if result["audit_trail_count_after_test"] > result["audit_trail_count_before_test"]:
                result["functional_test_passed"] = True
                
            cursor_sys.close()
            conn_sys.close()
            
        except Exception as e:
            result["test_query_error"] = str(e)

except Exception as e:
    result["error"] = str(e)

# 3. Check Evidence File
file_path = "/home/ga/Desktop/vip_audit_proof.csv"
if os.path.exists(file_path):
    result["evidence_file_exists"] = True
    # Check if it looks like a CSV with headers
    try:
        with open(file_path, 'r') as f:
            header = f.readline()
            if "DB_USER" in header.upper() or "SQL_TEXT" in header.upper():
                result["evidence_file_valid"] = True
            
            # Check file timestamp
            mtime = os.path.getmtime(file_path)
            task_start = float(os.environ.get("TASK_START", 0))
            result["file_created_during_task"] = (mtime > task_start)
    except:
        pass

# Save Result
with open("/tmp/fga_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print("Export complete.")
PYEOF

# Move result to safe location
mv /tmp/fga_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="