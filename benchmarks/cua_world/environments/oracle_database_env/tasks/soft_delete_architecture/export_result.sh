#!/bin/bash
# Export script for Soft Delete Architecture task
# Verifies schema structure, trigger logic, and performs a functional test

set -e
echo "=== Exporting Soft Delete Architecture Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We use Python for complex verification logic (checking structure and running test delete)
python3 << 'PYEOF'
import oracledb
import json
import os
import datetime

result = {
    "base_table_exists": False,
    "base_table_columns": [],
    "view_exists": False,
    "view_is_valid": False,
    "view_column_count": 0,
    "trigger_exists": False,
    "trigger_status": "UNKNOWN",
    "policy_1005_status": "UNKNOWN",
    "policy_1005_deleted_by": None,
    "policy_1005_deleted_at": None,
    "functional_test_passed": False,
    "functional_test_details": "",
    "export_timestamp": datetime.datetime.now().isoformat()
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Base Table Existence and Structure
    try:
        cursor.execute("SELECT column_name, data_type, nullable, data_default FROM user_tab_columns WHERE table_name = 'INSURANCE_POLICIES_BASE'")
        cols = cursor.fetchall()
        if cols:
            result["base_table_exists"] = True
            result["base_table_columns"] = [
                {"name": c[0], "type": c[1], "nullable": c[2]} for c in cols
            ]
    except Exception as e:
        result["base_table_error"] = str(e)

    # 2. Check View Existence
    try:
        cursor.execute("SELECT status FROM user_objects WHERE object_name = 'INSURANCE_POLICIES' AND object_type = 'VIEW'")
        row = cursor.fetchone()
        if row:
            result["view_exists"] = True
            result["view_is_valid"] = (row[0] == 'VALID')
            
            # Check view columns (should hide audit columns)
            cursor.execute("SELECT count(*) FROM user_tab_columns WHERE table_name = 'INSURANCE_POLICIES'")
            result["view_column_count"] = cursor.fetchone()[0]
    except Exception as e:
        result["view_error"] = str(e)

    # 3. Check Trigger Existence
    try:
        cursor.execute("""
            SELECT status, trigger_type, triggering_event 
            FROM user_triggers 
            WHERE table_name = 'INSURANCE_POLICIES' -- Trigger is on the VIEW
        """)
        row = cursor.fetchone()
        if row:
            result["trigger_exists"] = True
            result["trigger_status"] = row[0]
            result["trigger_type"] = row[1]
    except Exception as e:
        result["trigger_error"] = str(e)

    # 4. Check State of Policy 1005 (Agent was supposed to delete this)
    if result["base_table_exists"]:
        try:
            cursor.execute("SELECT is_active, deleted_by, deleted_at FROM insurance_policies_base WHERE policy_id = 1005")
            row = cursor.fetchone()
            if row:
                result["policy_1005_status"] = row[0] # Should be 'N'
                result["policy_1005_deleted_by"] = row[1]
                result["policy_1005_deleted_at"] = str(row[2])
            else:
                result["policy_1005_status"] = "MISSING" # Row physically deleted?
        except Exception as e:
            result["data_check_error"] = str(e)

    # 5. Functional Verification Test (The Verifier attempts a delete)
    # We try to delete Policy 1010 via the VIEW and check the BASE TABLE
    if result["view_exists"] and result["view_is_valid"]:
        try:
            # Attempt delete via view
            cursor.execute("DELETE FROM insurance_policies WHERE policy_id = 1010")
            conn.commit()
            
            # Check base table
            cursor.execute("SELECT is_active, deleted_by, deleted_at FROM insurance_policies_base WHERE policy_id = 1010")
            row = cursor.fetchone()
            
            if row:
                is_active, deleted_by, deleted_at = row
                if is_active == 'N' and deleted_at is not None:
                    result["functional_test_passed"] = True
                    result["functional_test_details"] = "Row 1010 updated to N"
                else:
                    result["functional_test_passed"] = False
                    result["functional_test_details"] = f"Row 1010 exists but IS_ACTIVE={is_active}"
            else:
                result["functional_test_passed"] = False
                result["functional_test_details"] = "Row 1010 was physically deleted from base table"
                
        except Exception as e:
            result["functional_test_passed"] = False
            result["functional_test_details"] = f"Error during test delete: {str(e)}"

    cursor.close()
    conn.close()

except Exception as e:
    result["global_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move result to safe location and ensure permissions
cp /tmp/task_result.json /tmp/soft_delete_result.json
chmod 666 /tmp/soft_delete_result.json

echo "Export complete."
cat /tmp/soft_delete_result.json