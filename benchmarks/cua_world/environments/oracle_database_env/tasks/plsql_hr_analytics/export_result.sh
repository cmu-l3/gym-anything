#!/bin/bash
# Export results for plsql_hr_analytics task

set -e

echo "=== Exporting PL/SQL HR Analytics Task Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/plsql_hr_analytics_final_screenshot.png

echo "[1/4] Querying package and object status..."
python3 << 'PYEOF'
import oracledb
import json
import os
import subprocess

result = {
    "package_exists": False,
    "package_status": "NOT FOUND",
    "dept_salary_stats_exists": False,
    "build_compensation_matrix_exists": False,
    "reporting_chain_exists": False,
    "compensation_matrix_table_exists": False,
    "compensation_table_row_count": 0,
    "compensation_table_columns": [],
    "grade_levels_present": [],
    "compensation_matrix_file_exists": False,
    "compensation_matrix_file_size": 0,
    "compensation_matrix_file_preview": "",
    "dept_salary_stats_test": "",
    "reporting_chain_test": "",
    "sample_row": {}
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Check package existence and status
    cursor.execute("""
        SELECT object_name, object_type, status
        FROM user_objects
        WHERE object_name = 'HR_ANALYTICS'
        ORDER BY object_type
    """)
    objects = cursor.fetchall()
    if objects:
        result["package_exists"] = True
        statuses = {row[1]: row[2] for row in objects}
        result["package_status"] = statuses.get("PACKAGE BODY", statuses.get("PACKAGE", "UNKNOWN"))

    # Check individual procedures/functions in the package
    cursor.execute("""
        SELECT procedure_name
        FROM user_procedures
        WHERE object_name = 'HR_ANALYTICS'
    """)
    procs = [row[0] for row in cursor.fetchall()]
    result["dept_salary_stats_exists"] = "DEPT_SALARY_STATS" in procs
    result["build_compensation_matrix_exists"] = "BUILD_COMPENSATION_MATRIX" in procs
    result["reporting_chain_exists"] = "REPORTING_CHAIN" in procs

    # Check COMPENSATION_MATRIX table
    cursor.execute("""
        SELECT COUNT(*) FROM user_tables WHERE table_name = 'COMPENSATION_MATRIX'
    """)
    row = cursor.fetchone()
    if row and row[0] > 0:
        result["compensation_matrix_table_exists"] = True

        # Row count
        cursor.execute("SELECT COUNT(*) FROM compensation_matrix")
        result["compensation_table_row_count"] = cursor.fetchone()[0]

        # Column names
        cursor.execute("""
            SELECT column_name FROM user_tab_columns
            WHERE table_name = 'COMPENSATION_MATRIX'
            ORDER BY column_id
        """)
        result["compensation_table_columns"] = [row[0] for row in cursor.fetchall()]

        # Grade levels present
        if "GRADE_LEVEL" in result["compensation_table_columns"]:
            cursor.execute("""
                SELECT DISTINCT grade_level FROM compensation_matrix
                WHERE grade_level IS NOT NULL
                ORDER BY grade_level
            """)
            result["grade_levels_present"] = [str(row[0]).strip() for row in cursor.fetchall()]

        # Sample row
        try:
            cursor.execute("""
                SELECT employee_id, full_name, job_title,
                       current_salary, dept_avg_salary,
                       salary_deviation_pct, grade_level
                FROM compensation_matrix
                WHERE ROWNUM = 1
            """)
            row = cursor.fetchone()
            if row:
                result["sample_row"] = {
                    "employee_id": row[0],
                    "full_name": str(row[1]) if row[1] else None,
                    "job_title": str(row[2]) if row[2] else None,
                    "current_salary": float(row[3]) if row[3] else None,
                    "dept_avg_salary": float(row[4]) if row[4] else None,
                    "salary_deviation_pct": float(row[5]) if row[5] else None,
                    "grade_level": str(row[6]).strip() if row[6] else None
                }
        except Exception as e:
            result["sample_row"] = {"error": str(e)}

    # Test DEPT_SALARY_STATS function if it exists
    if result["dept_salary_stats_exists"] and result["package_status"] == "VALID":
        try:
            cursor.execute("""
                SELECT hr_analytics.dept_salary_stats(90) FROM dual
            """)
            row = cursor.fetchone()
            if row:
                result["dept_salary_stats_test"] = str(row[0])
        except Exception as e:
            result["dept_salary_stats_test"] = f"ERROR: {str(e)[:200]}"

    # Test REPORTING_CHAIN function if it exists (employee 101 reports to King via Kochhar)
    if result["reporting_chain_exists"] and result["package_status"] == "VALID":
        try:
            cursor.execute("""
                SELECT hr_analytics.reporting_chain(101) FROM dual
            """)
            row = cursor.fetchone()
            if row:
                result["reporting_chain_test"] = str(row[0])
        except Exception as e:
            result["reporting_chain_test"] = f"ERROR: {str(e)[:200]}"

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)[:500]

# Check compensation_matrix.txt file
txt_path = "/home/ga/Desktop/compensation_matrix.txt"
if os.path.exists(txt_path):
    result["compensation_matrix_file_exists"] = True
    result["compensation_matrix_file_size"] = os.path.getsize(txt_path)
    try:
        with open(txt_path, "r") as f:
            content = f.read()
        # Preview first 500 chars
        result["compensation_matrix_file_preview"] = content[:500]
        # Count data lines
        lines = [l for l in content.splitlines() if l.strip() and not l.startswith("-") and not l.startswith("=")]
        result["compensation_matrix_file_line_count"] = len(lines)
    except Exception as e:
        result["compensation_matrix_file_preview"] = f"READ ERROR: {e}"

# Save result
with open("/tmp/plsql_hr_analytics_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "[2/4] Verifying result file..."
if [ -f "/tmp/plsql_hr_analytics_result.json" ]; then
    python3 -m json.tool /tmp/plsql_hr_analytics_result.json > /dev/null && echo "  Result JSON is valid"
else
    echo "  ERROR: Result JSON not created"
    exit 1
fi

echo "[3/4] Recording export timestamp..."
date +%s >> /tmp/task_start_timestamp

echo "[4/4] Copying final screenshot..."
cp /tmp/plsql_hr_analytics_final_screenshot.png /tmp/task_end_screenshot.png 2>/dev/null || true

echo "=== Export Complete ==="
echo "  Results saved to: /tmp/plsql_hr_analytics_result.json"
