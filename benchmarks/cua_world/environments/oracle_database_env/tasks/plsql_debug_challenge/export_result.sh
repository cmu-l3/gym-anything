#!/bin/bash
# Export script for PL/SQL Debug Challenge
# Executes comprehensive tests against the agent's modified code

set -e
echo "=== Exporting PL/SQL Debug Results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# --- Execute Tests via Python ---
# We use Python/oracledb to run specific test cases and capture return values safely
python3 << 'PYEOF'
import oracledb
import json
import os

result = {
    "compilation_status": {},
    "bug1_calc_comp_null": {"val": None, "passed": False},
    "bug1_calc_comp_valid": {"val": None, "passed": False},
    "bug2_ranking_check": {"rank": None, "salary": None, "passed": False},
    "bug3_top_earner": {"id": None, "passed": False},
    "bug4_percentile": {"val": None, "passed": False},
    "bug5_adjust_salary": {"old": 5000, "new": None, "passed": False},
    "bug_report_exists": False,
    "bug_report_size": 0
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Compilation Status
    objects = ['CALC_ANNUAL_COMPENSATION', 'BUILD_DEPT_SALARY_RANKINGS', 
               'FIND_DEPT_TOP_EARNER', 'GET_SALARY_PERCENTILE', 'ADJUST_SALARY']
    for obj in objects:
        cursor.execute("SELECT status FROM user_objects WHERE object_name = :1", [obj])
        row = cursor.fetchone()
        result["compilation_status"][obj] = row[0] if row else "MISSING"

    # 2. Test CALC_ANNUAL_COMPENSATION
    # ID 100 (King): Sal 24000, Comm NULL -> Expected 288000
    try:
        cursor.execute("SELECT calc_annual_compensation(100) FROM dual")
        val = cursor.fetchone()[0]
        result["bug1_calc_comp_null"]["val"] = float(val) if val is not None else None
        result["bug1_calc_comp_null"]["passed"] = (val == 288000)
    except Exception as e:
        result["bug1_calc_comp_null"]["error"] = str(e)

    # ID 145 (Russell): Sal 14000, Comm 0.4 -> Expected 14000*12*1.4 = 235200
    try:
        cursor.execute("SELECT calc_annual_compensation(145) FROM dual")
        val = cursor.fetchone()[0]
        result["bug1_calc_comp_valid"]["val"] = float(val) if val is not None else None
        result["bug1_calc_comp_valid"]["passed"] = (val == 235200)
    except Exception as e:
        result["bug1_calc_comp_valid"]["error"] = str(e)

    # 3. Test BUILD_DEPT_SALARY_RANKINGS
    # Check ID 100 (King) in Dept 90. He has highest salary (24000), should be Rank 1.
    # Buggy code (ASC) makes him Rank 3 (since there are 3 ppl and he is highest).
    try:
        cursor.execute("SELECT dept_rank, salary FROM dept_salary_rankings WHERE employee_id = 100")
        row = cursor.fetchone()
        if row:
            result["bug2_ranking_check"]["rank"] = row[0]
            result["bug2_ranking_check"]["salary"] = row[1]
            result["bug2_ranking_check"]["passed"] = (row[0] == 1)
    except Exception as e:
        result["bug2_ranking_check"]["error"] = str(e)

    # 4. Test FIND_DEPT_TOP_EARNER
    # Dept 90 top earner is 100. Buggy returns 102 (lowest).
    try:
        cursor.execute("SELECT find_dept_top_earner(90) FROM dual")
        val = cursor.fetchone()[0]
        result["bug3_top_earner"]["id"] = val
        result["bug3_top_earner"]["passed"] = (val == 100)
    except Exception as e:
        result["bug3_top_earner"]["error"] = str(e)

    # 5. Test GET_SALARY_PERCENTILE
    # ID 100 (King) is top in Dept 90 -> 100th percentile locally.
    # Globally he is also high, but we can differentiate.
    # Let's verify by logic: The percentile rank within dept 90 for King is 1.0 (100%).
    # The buggy global percentile for King is ~99%.
    # A better test: ID 104 (Bruce Ernst) in Dept 60.
    # Dept 60 salaries: 9000 (Hunold), 6000 (Ernst), 4800 (Austin), 4800 (Pataballa), 4200 (Lorentz).
    # Ernst (6000) is 2nd highest of 5? No, ranks:
    # 4200 (0%), 4800 (25%), 4800 (25%), 6000 (75%), 9000 (100%).
    # So Ernst should be 75.
    # Global percentile for 6000 is likely different.
    # Let's stick to King (100) who MUST be 100.
    try:
        cursor.execute("SELECT get_salary_percentile(100) FROM dual")
        val = cursor.fetchone()[0]
        result["bug4_percentile"]["val"] = val
        result["bug4_percentile"]["passed"] = (val == 100)
    except Exception as e:
        result["bug4_percentile"]["error"] = str(e)

    # 6. Test ADJUST_SALARY
    # Test Employee 250 (Salary 5000). Raise 10%.
    # Expected: 5500. Buggy: 5010.
    try:
        cursor.callproc("adjust_salary", [250, 10])
        cursor.execute("SELECT salary FROM employees WHERE employee_id = 250")
        val = cursor.fetchone()[0]
        result["bug5_adjust_salary"]["new"] = float(val)
        result["bug5_adjust_salary"]["passed"] = (val == 5500)
    except Exception as e:
        result["bug5_adjust_salary"]["error"] = str(e)

    cursor.close()
    conn.close()

except Exception as e:
    result["global_error"] = str(e)

# Check bug report file
if os.path.exists("/home/ga/Desktop/bug_report.txt"):
    result["bug_report_exists"] = True
    result["bug_report_size"] = os.path.getsize("/home/ga/Desktop/bug_report.txt")

with open("/tmp/plsql_debug_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Ensure file permissions
chmod 666 /tmp/plsql_debug_result.json 2>/dev/null || true

echo "Export complete. Result file:"
cat /tmp/plsql_debug_result.json