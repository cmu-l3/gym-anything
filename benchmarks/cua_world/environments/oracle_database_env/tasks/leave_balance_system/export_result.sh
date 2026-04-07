#!/bin/bash
# Export script for Leave Balance System task
# Inspects database schema, data, and logic (via test execution) to verify compliance

set -e
echo "=== Exporting Leave Balance System Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Run Python script inside the container to perform deep verification
# (checking schema objects, running logic tests, validating data)
python3 << 'PYEOF'
import oracledb
import json
import os
import datetime

result = {
    "tables_created": {},
    "constraints_valid": {},
    "columns_valid": {},
    "data_counts": {},
    "policy_logic_check": False,
    "accrual_logic_check": {},
    "procedure_status": "MISSING",
    "trigger_status": "MISSING",
    "trigger_functional_test": False,
    "trigger_enforcement_test": False,
    "report_file_exists": False,
    "report_file_valid": False,
    "timestamp": datetime.datetime.now().isoformat()
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Verify Tables and Columns
    tables_to_check = {
        "LEAVE_POLICIES": ["POLICY_ID", "JOB_ID", "ANNUAL_VACATION_DAYS", "ANNUAL_SICK_DAYS", "SENIORITY_BONUS_DAYS_PER_YEAR", "MAX_SENIORITY_BONUS"],
        "LEAVE_BALANCES": ["EMPLOYEE_ID", "LEAVE_TYPE", "BALANCE_DAYS", "LAST_ACCRUAL_DATE"],
        "LEAVE_REQUESTS": ["REQUEST_ID", "EMPLOYEE_ID", "LEAVE_TYPE", "START_DATE", "END_DATE", "DAYS_REQUESTED", "STATUS"]
    }

    for table, required_cols in tables_to_check.items():
        cursor.execute(f"SELECT count(*) FROM user_tables WHERE table_name = '{table}'")
        exists = cursor.fetchone()[0] > 0
        result["tables_created"][table] = exists
        
        if exists:
            # Check columns
            cursor.execute(f"SELECT column_name FROM user_tab_columns WHERE table_name = '{table}'")
            actual_cols = [r[0] for r in cursor.fetchall()]
            missing = [col for col in required_cols if col not in actual_cols]
            result["columns_valid"][table] = (len(missing) == 0)
            
            # Check row count
            cursor.execute(f"SELECT count(*) FROM {table}")
            result["data_counts"][table] = cursor.fetchone()[0]

    # 2. Verify Constraints (FKs and Checks)
    if result["tables_created"].get("LEAVE_POLICIES"):
        # Check Unique on JOB_ID
        cursor.execute("""
            SELECT count(*) FROM user_constraints 
            WHERE table_name = 'LEAVE_POLICIES' AND constraint_type IN ('U', 'P')
        """)
        result["constraints_valid"]["LEAVE_POLICIES_UK_PK"] = cursor.fetchone()[0] > 0

    if result["tables_created"].get("LEAVE_BALANCES"):
        # Check FK to Employees
        cursor.execute("""
            SELECT count(*) FROM user_constraints 
            WHERE table_name = 'LEAVE_BALANCES' AND constraint_type = 'R'
        """)
        result["constraints_valid"]["LEAVE_BALANCES_FK"] = cursor.fetchone()[0] > 0
        
        # Check Leave Type constraint (VACATION/SICK)
        cursor.execute("""
            SELECT count(*) FROM user_constraints 
            WHERE table_name = 'LEAVE_BALANCES' AND search_condition_vc LIKE '%VACATION%'
        """)
        result["constraints_valid"]["LEAVE_BALANCES_CHECK"] = cursor.fetchone()[0] > 0

    # 3. Verify Policy Logic (Check a few jobs)
    if result["data_counts"].get("LEAVE_POLICIES", 0) > 0:
        cursor.execute("SELECT annual_vacation_days FROM leave_policies WHERE job_id = 'AD_PRES'")
        row = cursor.fetchone()
        ad_pres_days = row[0] if row else 0
        
        cursor.execute("SELECT annual_vacation_days FROM leave_policies WHERE job_id = 'IT_PROG'")
        row = cursor.fetchone()
        it_prog_days = row[0] if row else 0
        
        # Expect AD_PRES (25) > IT_PROG (15)
        result["policy_logic_check"] = (ad_pres_days == 25 and it_prog_days == 15)

    # 4. Verify Accrual Logic (Seniority)
    if result["data_counts"].get("LEAVE_BALANCES", 0) > 0:
        # Get Steven King (ID 100, hired 2003, max seniority) vs a newer employee
        # King: AD_PRES (25) + Max Bonus (10) = 35
        cursor.execute("SELECT balance_days FROM leave_balances WHERE employee_id = 100 AND leave_type = 'VACATION'")
        row = cursor.fetchone()
        king_bal = row[0] if row else 0
        
        # Diana Lorentz (ID 107, IT_PROG, hired 2007, ~17 yrs service). 
        # IT_PROG Base 15 + Max Bonus 10 = 25.
        cursor.execute("SELECT balance_days FROM leave_balances WHERE employee_id = 107 AND leave_type = 'VACATION'")
        row = cursor.fetchone()
        diana_bal = row[0] if row else 0
        
        result["accrual_logic_check"] = {
            "king_balance": float(king_bal),
            "diana_balance": float(diana_bal),
            "logic_passed": (king_bal >= 35 and diana_bal >= 25)
        }

    # 5. Verify Procedure and Trigger Status
    cursor.execute("SELECT status FROM user_objects WHERE object_name = 'CALCULATE_LEAVE_ACCRUALS' AND object_type = 'PROCEDURE'")
    row = cursor.fetchone()
    if row: result["procedure_status"] = row[0]

    cursor.execute("SELECT status FROM user_triggers WHERE trigger_name = 'TRG_LEAVE_BALANCE_CHECK'")
    row = cursor.fetchone()
    if row: result["trigger_status"] = row[0]

    # 6. Functional Test of Trigger
    if result["trigger_status"] == 'VALID':
        # Test A: Insufficient Funds (Should Fail)
        # King has ~35 days. Try to request 100.
        try:
            cursor.execute("""
                INSERT INTO leave_requests (request_id, employee_id, leave_type, start_date, end_date, days_requested, status)
                VALUES (999998, 100, 'VACATION', SYSDATE, SYSDATE+100, 100, 'APPROVED')
            """)
            # If we get here, trigger failed to block
            result["trigger_enforcement_test"] = False
            # Rollback just in case
            conn.rollback()
        except oracledb.DatabaseError as e:
            error, = e.args
            # Expecting custom error or check constraint failure
            if '2000' in str(error.code) or '20001' in str(error.message) or 'check constraint' in str(error.message).lower():
                result["trigger_enforcement_test"] = True
            else:
                # Some other error occurred
                result["trigger_enforcement_error"] = str(e)

        # Test B: Valid Request (Should Deduct)
        # Get current balance
        cursor.execute("SELECT balance_days FROM leave_balances WHERE employee_id = 100 AND leave_type = 'VACATION'")
        initial_bal = cursor.fetchone()[0]
        
        try:
            cursor.execute("""
                INSERT INTO leave_requests (request_id, employee_id, leave_type, start_date, end_date, days_requested, status)
                VALUES (999999, 100, 'VACATION', SYSDATE, SYSDATE+1, 1, 'APPROVED')
            """)
            
            cursor.execute("SELECT balance_days FROM leave_balances WHERE employee_id = 100 AND leave_type = 'VACATION'")
            new_bal = cursor.fetchone()[0]
            
            if new_bal == initial_bal - 1:
                result["trigger_functional_test"] = True
            
            conn.rollback() # Cleanup test data
        except Exception as e:
            result["trigger_functional_error"] = str(e)

    cursor.close()
    conn.close()

except Exception as e:
    result["error"] = str(e)

# 7. Verify Output File
report_path = "/home/ga/Desktop/leave_balance_report.txt"
if os.path.exists(report_path):
    result["report_file_exists"] = True
    size = os.path.getsize(report_path)
    if size > 100:
        with open(report_path, 'r') as f:
            lines = f.readlines()
            # Basic content check
            if len(lines) > 50 and "VACATION" in f.read(): # reading again from start requires seek, but simple check is enough
                pass # logic simplified
            
            # Better check
            has_vacation = any("VACATION" in l for l in lines)
            has_sick = any("SICK" in l for l in lines)
            has_king = any("King" in l for l in lines)
            
            if len(lines) > 200 and has_vacation and has_sick and has_king:
                result["report_file_valid"] = True
            
            result["report_line_count"] = len(lines)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export verification complete.")
PYEOF

cat /tmp/task_result.json
echo "=== Export Complete ==="