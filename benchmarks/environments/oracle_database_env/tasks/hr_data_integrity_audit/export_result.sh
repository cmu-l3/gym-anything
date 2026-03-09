#!/bin/bash
# Export verification data for hr_data_integrity_audit task
# Checks which planted issues remain unresolved and whether an audit report was created.

echo "=== Exporting HR Data Integrity Audit Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read baseline
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Use Python/oracledb for reliable multi-query export
python3 << 'PYEOF'
import oracledb
import json
import os
import sys

result = {
    "salary_violations_remaining": -1,
    "salary_violations_remaining_ids": [],
    "future_dates_remaining": -1,
    "future_dates_remaining_ids": [],
    "null_dept_remaining": -1,
    "null_dept_remaining_ids": [],
    "audit_report_exists": False,
    "audit_report_size": 0,
    "audit_report_preview": "",
    "any_audit_table_created": False,
    "export_timestamp": ""
}

try:
    import datetime
    result["export_timestamp"] = datetime.datetime.now().isoformat()

    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # --- Check salary violations remaining for planted employees ---
    # Salary violation = salary outside job's MIN_SALARY..MAX_SALARY
    cursor.execute("""
        SELECT e.employee_id
        FROM employees e
        JOIN jobs j ON e.job_id = j.job_id
        WHERE e.employee_id BETWEEN 300 AND 304
          AND (e.salary < j.min_salary OR e.salary > j.max_salary)
        ORDER BY e.employee_id
    """)
    sal_rows = cursor.fetchall()
    result["salary_violations_remaining"] = len(sal_rows)
    result["salary_violations_remaining_ids"] = [r[0] for r in sal_rows]

    # --- Check future hire dates remaining ---
    cursor.execute("""
        SELECT employee_id
        FROM employees
        WHERE employee_id BETWEEN 305 AND 308
          AND hire_date > SYSDATE
        ORDER BY employee_id
    """)
    date_rows = cursor.fetchall()
    result["future_dates_remaining"] = len(date_rows)
    result["future_dates_remaining_ids"] = [r[0] for r in date_rows]

    # --- Check null department remaining ---
    cursor.execute("""
        SELECT employee_id
        FROM employees
        WHERE employee_id BETWEEN 309 AND 311
          AND department_id IS NULL
          AND manager_id IS NOT NULL
        ORDER BY employee_id
    """)
    dept_rows = cursor.fetchall()
    result["null_dept_remaining"] = len(dept_rows)
    result["null_dept_remaining_ids"] = [r[0] for r in dept_rows]

    # --- Check if any audit/log table was created by the agent ---
    cursor.execute("""
        SELECT COUNT(*) FROM user_tables
        WHERE UPPER(table_name) LIKE '%AUDIT%'
           OR UPPER(table_name) LIKE '%LOG%'
           OR UPPER(table_name) LIKE '%REMEDIAT%'
    """)
    audit_table_count = cursor.fetchone()[0]
    result["any_audit_table_created"] = (audit_table_count > 0)

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# --- Check audit report file ---
report_path = "/home/ga/Desktop/hr_audit_report.txt"
if os.path.exists(report_path):
    result["audit_report_exists"] = True
    result["audit_report_size"] = os.path.getsize(report_path)
    try:
        with open(report_path, "r", errors="replace") as f:
            content = f.read(3000)
        result["audit_report_preview"] = content
    except Exception:
        pass

with open("/tmp/hr_data_integrity_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete. Results written to /tmp/hr_data_integrity_audit_result.json")
PYEOF

# Validate the JSON
python3 -c "import json; json.load(open('/tmp/hr_data_integrity_audit_result.json'))" && echo "[OK] JSON is valid" || echo "[WARN] JSON may be invalid"

echo "=== Export Complete ==="
