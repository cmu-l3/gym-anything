#!/bin/bash
# Export script for comp_benchmark_mviews task
# Inspects Oracle data dictionary and output file to verify task completion

set -e
echo "=== Exporting Compensation Benchmark MViews Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use Python to query Oracle and construct JSON result
# This handles the complexity of checking multiple MVs, columns, and data values safely
python3 << 'PYEOF'
import oracledb
import json
import os
import sys

result = {
    "task_start": int(os.environ.get('TASK_START', 0)),
    "task_end": int(os.environ.get('TASK_END', 0)),
    "mvs": {},
    "procedure": {"exists": False, "status": "UNKNOWN"},
    "export_file": {"exists": False, "size": 0, "created_during_task": False},
    "db_error": None
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Check Materialized Views
    target_mvs = ["MV_DEPT_COMP_SUMMARY", "MV_JOB_SALARY_BANDS", "MV_HIRE_DECADE_STATS"]
    
    for mv_name in target_mvs:
        mv_info = {
            "exists": False,
            "columns": [],
            "row_count": 0,
            "refresh_mode": None,
            "refresh_method": None,
            "sample_data": None
        }
        
        # Check existence and config
        cursor.execute("""
            SELECT refresh_mode, refresh_method 
            FROM user_mviews 
            WHERE mview_name = :mv
        """, [mv_name])
        row = cursor.fetchone()
        if row:
            mv_info["exists"] = True
            mv_info["refresh_mode"] = row[0]
            mv_info["refresh_method"] = row[1]
            
            # Get columns
            cursor.execute("""
                SELECT column_name 
                FROM user_tab_columns 
                WHERE table_name = :mv 
                ORDER BY column_id
            """, [mv_name])
            mv_info["columns"] = [r[0] for r in cursor.fetchall()]
            
            # Get row count
            cursor.execute(f"SELECT COUNT(*) FROM {mv_name}")
            mv_info["row_count"] = cursor.fetchone()[0]
            
            # Get sample data for spot checks
            if mv_name == "MV_DEPT_COMP_SUMMARY":
                # Check Dept 90 (Executive)
                try:
                    cursor.execute(f"SELECT employee_count, total_payroll FROM {mv_name} WHERE department_id = 90")
                    s_row = cursor.fetchone()
                    if s_row:
                        mv_info["sample_data"] = {"dept_90_emp_count": s_row[0], "dept_90_payroll": s_row[1]}
                except: pass
                
            elif mv_name == "MV_JOB_SALARY_BANDS":
                # Check SA_REP
                try:
                    cursor.execute(f"SELECT employee_count FROM {mv_name} WHERE job_id = 'SA_REP'")
                    s_row = cursor.fetchone()
                    if s_row:
                        mv_info["sample_data"] = {"sa_rep_count": s_row[0]}
                except: pass
                
            elif mv_name == "MV_HIRE_DECADE_STATS":
                # Check for 2000s
                try:
                    cursor.execute(f"SELECT count(*) FROM {mv_name} WHERE hire_decade LIKE '%2000%'")
                    s_row = cursor.fetchone()
                    if s_row and s_row[0] > 0:
                        mv_info["sample_data"] = {"has_2000s": True}
                except: pass

        result["mvs"][mv_name] = mv_info

    # 2. Check Procedure
    cursor.execute("""
        SELECT status 
        FROM user_objects 
        WHERE object_name = 'REFRESH_COMP_VIEWS' 
        AND object_type = 'PROCEDURE'
    """)
    proc_row = cursor.fetchone()
    if proc_row:
        result["procedure"]["exists"] = True
        result["procedure"]["status"] = proc_row[0]

    # 3. Test Procedure Execution (if valid)
    if result["procedure"]["status"] == 'VALID':
        try:
            cursor.callproc("REFRESH_COMP_VIEWS")
            result["procedure"]["execution_success"] = True
        except Exception as e:
            result["procedure"]["execution_success"] = False
            result["procedure"]["execution_error"] = str(e)

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# 4. Check Output File
file_path = "/home/ga/Desktop/compensation_benchmark.txt"
if os.path.exists(file_path):
    stats = os.stat(file_path)
    result["export_file"]["exists"] = True
    result["export_file"]["size"] = stats.st_size
    # Check if created after task start
    if stats.st_mtime > result["task_start"]:
        result["export_file"]["created_during_task"] = True
    
    # Read a bit of content for keywords
    try:
        with open(file_path, 'r', errors='ignore') as f:
            content = f.read(2000)
            result["export_file"]["preview"] = content
    except:
        pass

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json