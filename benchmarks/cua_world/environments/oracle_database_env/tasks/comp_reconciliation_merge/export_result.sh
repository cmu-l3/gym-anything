#!/bin/bash
# Export script for Compensation Reconciliation Task
# Verifies the state of EMPLOYEES and SALARY_CHANGE_LOG tables

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Export verification data using Python
python3 << 'PYEOF'
import oracledb
import json
import os
import sys

# Verification Constants
GROUP_A_IDS = [105, 106, 107, 115, 116, 117, 119, 125, 126, 127, 131, 132, 136, 140, 144]
GROUP_A_MARKET = {
    105: 6000, 106: 5800, 107: 5200, 115: 3800, 116: 3600, 117: 3500, 119: 3200, 
    125: 4000, 126: 3400, 127: 3100, 131: 3200, 132: 2700, 136: 2800, 140: 3200, 144: 3100
}

GROUP_B_IDS = [100, 101, 102, 103, 104, 108, 109]
GROUP_B_ORIGINAL = {
    100: 24000, 101: 17000, 102: 17000, 103: 9000, 104: 6000, 108: 12008, 109: 9000
}

GROUP_C_NAMES = [
    ('Rachel', 'Morrison'), ('Derek', 'Tanaka'), ('Simone', 'Beaumont'), 
    ('Kwame', 'Asante'), ('Lena', 'Volkov'), ('Marco', 'Ricci'), 
    ('Anika', 'Patel'), ('Tobias', 'Reinhardt')
]

result = {
    "audit_table_exists": False,
    "audit_columns_valid": False,
    "audit_row_count": 0,
    "audit_types_found": [],
    "group_a_updates_correct": 0,
    "group_b_unchanged_correct": 0,
    "group_c_inserts_correct": 0,
    "total_employee_count": 0,
    "report_exists": False,
    "report_size": 0,
    "errors": []
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Audit Table
    try:
        cursor.execute("SELECT count(*) FROM user_tables WHERE table_name = 'SALARY_CHANGE_LOG'")
        if cursor.fetchone()[0] > 0:
            result["audit_table_exists"] = True
            
            # Check columns
            cursor.execute("SELECT column_name FROM user_tab_columns WHERE table_name = 'SALARY_CHANGE_LOG'")
            cols = [r[0] for r in cursor.fetchall()]
            required = ['EMPLOYEE_ID', 'OLD_SALARY', 'NEW_SALARY', 'CHANGE_TYPE']
            if all(req in cols for req in required):
                result["audit_columns_valid"] = True
            
            # Check content
            cursor.execute("SELECT count(*) FROM salary_change_log")
            result["audit_row_count"] = cursor.fetchone()[0]
            
            cursor.execute("SELECT DISTINCT change_type FROM salary_change_log")
            result["audit_types_found"] = [r[0] for r in cursor.fetchall()]
    except Exception as e:
        result["errors"].append(f"Audit table check failed: {str(e)}")

    # 2. Verify Group A (Updates)
    success_a = 0
    for eid in GROUP_A_IDS:
        cursor.execute("SELECT salary FROM employees WHERE employee_id = :1", [eid])
        row = cursor.fetchone()
        if row and row[0] == GROUP_A_MARKET[eid]:
            success_a += 1
    result["group_a_updates_correct"] = success_a

    # 3. Verify Group B (No Updates)
    success_b = 0
    for eid in GROUP_B_IDS:
        cursor.execute("SELECT salary FROM employees WHERE employee_id = :1", [eid])
        row = cursor.fetchone()
        if row and row[0] == GROUP_B_ORIGINAL[eid]:
            success_b += 1
    result["group_b_unchanged_correct"] = success_b

    # 4. Verify Group C (Inserts)
    success_c = 0
    for first, last in GROUP_C_NAMES:
        cursor.execute("SELECT count(*) FROM employees WHERE first_name = :1 AND last_name = :2", [first, last])
        if cursor.fetchone()[0] > 0:
            success_c += 1
    result["group_c_inserts_correct"] = success_c

    # 5. Total Count
    cursor.execute("SELECT count(*) FROM employees")
    result["total_employee_count"] = cursor.fetchone()[0]
    
    conn.close()

except Exception as e:
    result["errors"].append(f"DB verification failed: {str(e)}")

# 6. Check Report File
report_path = "/home/ga/Desktop/reconciliation_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_size"] = os.path.getsize(report_path)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json