#!/bin/bash
# Export script for Workforce Optimization Views task
# Inspects Oracle database objects and CSV files to generate verification JSON

set -e

echo "=== Exporting Workforce Optimization Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Run Python script to inspect DB and Files
python3 << 'PYEOF'
import oracledb
import json
import os
import csv
import sys

# Initialize result dictionary
result = {
    "org_hierarchy_vw": {"exists": False, "valid": False, "columns": [], "row_count": 0, "sample_root": {}, "sample_leaf": {}},
    "salary_analytics_vw": {"exists": False, "valid": False, "columns": [], "row_count": 0, "sample_data": {}},
    "dept_job_crosstab": {"exists": False, "columns": [], "row_count": 0, "sample_it": {}},
    "csv_files": {
        "org_hierarchy": {"exists": False, "size": 0, "lines": 0},
        "salary_analytics": {"exists": False, "size": 0, "lines": 0},
        "dept_job_matrix": {"exists": False, "size": 0, "lines": 0}
    },
    "db_error": None
}

try:
    # Connect to Oracle
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # --- 1. Check ORG_HIERARCHY_VW ---
    cursor.execute("SELECT status FROM user_objects WHERE object_name = 'ORG_HIERARCHY_VW' AND object_type = 'VIEW'")
    row = cursor.fetchone()
    if row:
        result["org_hierarchy_vw"]["exists"] = True
        result["org_hierarchy_vw"]["valid"] = (row[0] == 'VALID')
        
        # Get Columns
        cursor.execute("SELECT column_name FROM user_tab_columns WHERE table_name = 'ORG_HIERARCHY_VW'")
        result["org_hierarchy_vw"]["columns"] = [r[0] for r in cursor.fetchall()]
        
        # Get Count
        try:
            cursor.execute("SELECT COUNT(*) FROM ORG_HIERARCHY_VW")
            result["org_hierarchy_vw"]["row_count"] = cursor.fetchone()[0]
            
            # Spot Check Root (Steven King)
            cursor.execute("""
                SELECT hierarchy_level, manager_name, reporting_path 
                FROM ORG_HIERARCHY_VW WHERE employee_id = 100
            """)
            root_data = cursor.fetchone()
            if root_data:
                result["org_hierarchy_vw"]["sample_root"] = {
                    "level": root_data[0],
                    "manager": root_data[1],
                    "path": root_data[2]
                }
                
            # Spot Check Leaf (e.g. 103 - Alexander Hunold, reports to Lex De Haan reports to King)
            # Actually 103 reports to 102 who reports to 100.
            cursor.execute("""
                SELECT hierarchy_level, reporting_path 
                FROM ORG_HIERARCHY_VW WHERE employee_id = 103
            """)
            leaf_data = cursor.fetchone()
            if leaf_data:
                 result["org_hierarchy_vw"]["sample_leaf"] = {
                    "level": leaf_data[0],
                    "path": leaf_data[1]
                }
        except Exception as e:
            result["org_hierarchy_vw"]["error"] = str(e)

    # --- 2. Check SALARY_BAND_ANALYTICS_VW ---
    cursor.execute("SELECT status FROM user_objects WHERE object_name = 'SALARY_BAND_ANALYTICS_VW' AND object_type = 'VIEW'")
    row = cursor.fetchone()
    if row:
        result["salary_analytics_vw"]["exists"] = True
        result["salary_analytics_vw"]["valid"] = (row[0] == 'VALID')
        
        cursor.execute("SELECT column_name FROM user_tab_columns WHERE table_name = 'SALARY_BAND_ANALYTICS_VW'")
        result["salary_analytics_vw"]["columns"] = [r[0] for r in cursor.fetchall()]
        
        try:
            cursor.execute("SELECT COUNT(*) FROM SALARY_BAND_ANALYTICS_VW")
            result["salary_analytics_vw"]["row_count"] = cursor.fetchone()[0]
            
            # Spot Check Dept 90 (King 24000, Kochhar 17000, De Haan 17000)
            # King should be rank 1.
            cursor.execute("""
                SELECT dept_salary_rank, salary_quartile, deviation_from_dept_avg 
                FROM SALARY_BAND_ANALYTICS_VW WHERE employee_id = 100
            """)
            king_data = cursor.fetchone()
            if king_data:
                result["salary_analytics_vw"]["sample_data"] = {
                    "king_rank": king_data[0],
                    "king_quartile": king_data[1],
                    "king_deviation": king_data[2]
                }
        except Exception as e:
            result["salary_analytics_vw"]["error"] = str(e)

    # --- 3. Check DEPT_JOB_CROSSTAB ---
    cursor.execute("SELECT status FROM user_objects WHERE object_name = 'DEPT_JOB_CROSSTAB' AND object_type = 'TABLE'")
    row = cursor.fetchone()
    if row:
        result["dept_job_crosstab"]["exists"] = True
        
        cursor.execute("SELECT column_name FROM user_tab_columns WHERE table_name = 'DEPT_JOB_CROSSTAB'")
        result["dept_job_crosstab"]["columns"] = [r[0] for r in cursor.fetchall()]
        
        try:
            cursor.execute("SELECT COUNT(*) FROM DEPT_JOB_CROSSTAB")
            result["dept_job_crosstab"]["row_count"] = cursor.fetchone()[0]
            
            # Spot Check IT Department (Dept 60)
            # Should have IT=5
            # We need to find the column that corresponds to 'IT'. 
            # Note: Oracle identifiers are usually uppercase.
            cursor.execute("SELECT IT FROM DEPT_JOB_CROSSTAB WHERE DEPARTMENT_NAME = 'IT'")
            it_val = cursor.fetchone()
            if it_val:
                result["dept_job_crosstab"]["sample_it"] = it_val[0]
        except Exception as e:
            result["dept_job_crosstab"]["error"] = str(e)

    cursor.close()
    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# --- 4. Check CSV Files ---
def check_csv(path, key):
    if os.path.exists(path):
        result["csv_files"][key]["exists"] = True
        result["csv_files"][key]["size"] = os.path.getsize(path)
        try:
            with open(path, 'r') as f:
                result["csv_files"][key]["lines"] = sum(1 for line in f)
        except:
            pass

check_csv("/home/ga/Desktop/org_hierarchy.csv", "org_hierarchy")
check_csv("/home/ga/Desktop/salary_analytics.csv", "salary_analytics")
check_csv("/home/ga/Desktop/dept_job_matrix.csv", "dept_job_matrix")

# Write result
with open("/tmp/workforce_optimization_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print("Export verification complete.")
PYEOF

echo "Results saved to /tmp/workforce_optimization_result.json"