#!/bin/bash
# Export script for Compound Trigger Budget Protection task
# Runs a Python script INSIDE the container to functionally test the trigger logic.
# This approach is required because we need to attempt invalid updates and catch exceptions.

set -e

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Create the test script
cat > /tmp/test_trigger.py << 'PYEOF'
import oracledb
import json
import datetime

result = {
    "table_exists": False,
    "columns_correct": False,
    "data_calculation_correct": False,
    "trigger_exists": False,
    "trigger_status": "UNKNOWN",
    "trigger_type": "UNKNOWN",
    "test_massive_raise_blocked": False,
    "test_small_raise_allowed": False,
    "test_bulk_update_blocked": False,
    "test_transfer_blocked": False,
    "error_message_correct": False,
    "mutating_table_error": False,
    "details": []
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Table Structure
    try:
        cursor.execute("SELECT count(*) FROM user_tables WHERE table_name = 'DEPT_SPENDING_CAPS'")
        if cursor.fetchone()[0] == 1:
            result["table_exists"] = True
            cursor.execute("SELECT column_name FROM user_tab_columns WHERE table_name = 'DEPT_SPENDING_CAPS'")
            cols = {r[0] for r in cursor.fetchall()}
            if "DEPARTMENT_ID" in cols and "CAP_AMOUNT" in cols:
                result["columns_correct"] = True
    except Exception as e:
        result["details"].append(f"Table check error: {str(e)}")

    # 2. Check Data Logic (Sum * 1.20)
    # We'll check Dept 60 (IT).
    # First, calculate what it SHOULD be based on current employees
    try:
        cursor.execute("SELECT SUM(salary) FROM employees WHERE department_id = 60")
        current_sum = cursor.fetchone()[0] or 0
        expected_cap = round(current_sum * 1.20)
        
        cursor.execute("SELECT cap_amount FROM dept_spending_caps WHERE department_id = 60")
        row = cursor.fetchone()
        if row:
            actual_cap = row[0]
            # Allow +/- 1 rounding difference
            if abs(actual_cap - expected_cap) <= 1:
                result["data_calculation_correct"] = True
            else:
                result["details"].append(f"Cap mismatch for Dept 60. Expected ~{expected_cap}, got {actual_cap}")
        else:
            result["details"].append("No cap record for Dept 60")
    except Exception as e:
        result["details"].append(f"Data check error: {str(e)}")

    # 3. Check Trigger Existence
    try:
        cursor.execute("SELECT status, trigger_type FROM user_triggers WHERE trigger_name = 'TRG_ENFORCE_SPENDING_CAP'")
        row = cursor.fetchone()
        if row:
            result["trigger_exists"] = True
            result["trigger_status"] = row[0]
            result["trigger_type"] = row[1]
    except Exception as e:
        result["details"].append(f"Trigger check error: {str(e)}")

    # 4. Functional Test: Massive Raise (Should Fail)
    # Dept 60 has ~20% buffer. Adding 1,000,000 should fail.
    if result["trigger_exists"] and result["trigger_status"] == 'ENABLED':
        try:
            # Employee 103 is Alexander Hunold in Dept 60
            cursor.execute("UPDATE employees SET salary = salary + 1000000 WHERE employee_id = 103")
            # If we get here, it didn't block
            result["test_massive_raise_blocked"] = False
            conn.rollback() # Rollback the bad data if it somehow succeeded
        except oracledb.DatabaseError as e:
            error, = e.args
            msg = error.message
            if "ORA-20001" in msg:
                result["test_massive_raise_blocked"] = True
                if "Budget" in msg or "BUDGET" in msg:
                    result["error_message_correct"] = True
            elif "ORA-04091" in msg:
                result["mutating_table_error"] = True
                result["details"].append("Trigger failed with Mutating Table error")
            else:
                result["details"].append(f"Blocked with unexpected error: {msg}")

        # 5. Functional Test: Small Raise (Should Succeed)
        # Adding 10 to salary is well within 20% buffer
        try:
            cursor.execute("UPDATE employees SET salary = salary + 10 WHERE employee_id = 103")
            result["test_small_raise_allowed"] = True
            conn.rollback() # Reset state
        except Exception as e:
            result["details"].append(f"Valid small raise failed: {str(e)}")

        # 6. Functional Test: Bulk Update (Should Fail)
        # Doubling salaries in dept 60 will exceed 20% buffer
        try:
            cursor.execute("UPDATE employees SET salary = salary * 2 WHERE department_id = 60")
            result["test_bulk_update_blocked"] = False
            conn.rollback()
        except oracledb.DatabaseError as e:
            error, = e.args
            if "ORA-20001" in error.message:
                result["test_bulk_update_blocked"] = True

        # 7. Functional Test: Transfer (Should Fail)
        # Move high earner (Emp 100, Steven King, ~24k) to Administration (Dept 10, Cap ~5k)
        try:
            cursor.execute("UPDATE employees SET department_id = 10 WHERE employee_id = 100")
            result["test_transfer_blocked"] = False
            conn.rollback()
        except oracledb.DatabaseError as e:
            error, = e.args
            if "ORA-20001" in error.message:
                result["test_transfer_blocked"] = True

    cursor.close()
    conn.close()

except Exception as e:
    result["details"].append(f"Script crash: {str(e)}")

with open('/tmp/trigger_test_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Run the python script
python3 /tmp/test_trigger.py

# Export result
mv /tmp/trigger_test_result.json /tmp/compound_trigger_result.json
chmod 666 /tmp/compound_trigger_result.json

echo "Results exported to /tmp/compound_trigger_result.json"