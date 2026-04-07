#!/bin/bash
# Export script for Salary Audit Triggers task
# Inspects database objects, data content, and trigger behavior using python/oracledb

set -e
echo "=== Exporting Salary Audit Triggers Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We use python for robust JSON export
python3 << 'PYEOF'
import oracledb
import json
import os
import datetime

result = {
    "objects": {},
    "audit_log_data": [],
    "employee_state": {},
    "trigger_behavior_test": {},
    "file_check": {},
    "timestamp": datetime.datetime.now().isoformat()
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # --- 1. Check Object Existence & Status ---
    objects_to_check = ["AUDIT_SEQ", "SALARY_AUDIT_LOG", "TRG_SALARY_AUDIT", "TRG_PREVENT_MANAGER_DELETE"]
    for obj in objects_to_check:
        cursor.execute("SELECT object_type, status FROM user_objects WHERE object_name = :1", [obj])
        row = cursor.fetchone()
        if row:
            result["objects"][obj] = {"exists": True, "type": row[0], "status": row[1]}
        else:
            result["objects"][obj] = {"exists": False, "status": "MISSING"}

    # --- 2. Check Table Structure ---
    if result["objects"].get("SALARY_AUDIT_LOG", {}).get("exists"):
        cursor.execute("SELECT column_name, data_type FROM user_tab_columns WHERE table_name = 'SALARY_AUDIT_LOG'")
        cols = {row[0]: row[1] for row in cursor.fetchall()}
        result["objects"]["SALARY_AUDIT_LOG"]["columns"] = cols
        
        # Check constraints (PK)
        cursor.execute("""
            SELECT constraint_type FROM user_constraints 
            WHERE table_name = 'SALARY_AUDIT_LOG' AND constraint_type = 'P'
        """)
        result["objects"]["SALARY_AUDIT_LOG"]["has_pk"] = (cursor.fetchone() is not None)

    # --- 3. Check Audit Log Content ---
    if result["objects"].get("SALARY_AUDIT_LOG", {}).get("exists"):
        cursor.execute("""
            SELECT employee_id, change_type, old_value, new_value 
            FROM salary_audit_log 
            ORDER BY audit_id
        """)
        # Convert rows to dicts
        logs = []
        for r in cursor.fetchall():
            logs.append({
                "employee_id": r[0],
                "change_type": r[1],
                "old_value": r[2],
                "new_value": r[3]
            })
        result["audit_log_data"] = logs

    # --- 4. Check Employee State (Verification of DML) ---
    cursor.execute("SELECT salary FROM employees WHERE employee_id = 200")
    res = cursor.fetchone()
    result["employee_state"]["emp_200_salary"] = res[0] if res else None

    cursor.execute("SELECT department_id FROM employees WHERE employee_id = 105")
    res = cursor.fetchone()
    result["employee_state"]["emp_105_dept"] = res[0] if res else None

    cursor.execute("SELECT job_id FROM employees WHERE employee_id = 206")
    res = cursor.fetchone()
    result["employee_state"]["emp_206_job"] = res[0] if res else None

    cursor.execute("SELECT COUNT(*) FROM employees WHERE employee_id = 100")
    result["employee_state"]["emp_100_exists"] = (cursor.fetchone()[0] == 1)

    # --- 5. Dynamic Trigger Test (The "Verifier's Poke") ---
    # We attempt to delete a manager (Emp 100) to see if the trigger blocks US
    # This confirms the trigger is actually active and logic is correct, 
    # not just that the agent didn't delete the row.
    try:
        cursor.execute("DELETE FROM employees WHERE employee_id = 100")
        # If we reach here, the delete succeeded (BAD)
        conn.rollback() # Restore state
        result["trigger_behavior_test"]["delete_manager_blocked"] = False
        result["trigger_behavior_test"]["message"] = "Delete succeeded (trigger failed to block)"
    except oracledb.DatabaseError as e:
        error_obj = e.args[0]
        # ORA-20001 is the expected custom error
        if "ORA-20001" in error_obj.message:
            result["trigger_behavior_test"]["delete_manager_blocked"] = True
            result["trigger_behavior_test"]["message"] = "Blocked with correct ORA-20001"
        # ORA-02292 is Integrity Constraint violation (child records found)
        # If standard FKs are in place, this might hit first if the trigger isn't working/firing BEFORE.
        # But task requires BEFORE DELETE trigger which should fire before FK check.
        # However, Oracle order of operations: BEFORE triggers fire -> Constraints checked.
        # So if we hit constraint error, trigger might be missing or broken.
        else:
            result["trigger_behavior_test"]["delete_manager_blocked"] = False
            result["trigger_behavior_test"]["message"] = f"Blocked but wrong error: {error_obj.message}"

    conn.close()

except Exception as e:
    result["error"] = str(e)

# --- 6. File Check ---
log_path = "/home/ga/Desktop/audit_log.txt"
if os.path.exists(log_path):
    result["file_check"]["exists"] = True
    result["file_check"]["size"] = os.path.getsize(log_path)
    try:
        with open(log_path, 'r') as f:
            result["file_check"]["content_preview"] = f.read(500)
    except:
        result["file_check"]["content_preview"] = "Error reading file"
else:
    result["file_check"]["exists"] = False

# Save result
with open("/tmp/salary_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export logic complete.")
PYEOF

# Move and verify
chmod 666 /tmp/salary_audit_result.json
echo "Result JSON generated at /tmp/salary_audit_result.json"