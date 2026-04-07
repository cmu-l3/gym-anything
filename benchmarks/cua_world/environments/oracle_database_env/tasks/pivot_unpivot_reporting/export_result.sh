#!/bin/bash
# Export script for Pivot/Unpivot Reporting task

set -e
echo "=== Exporting Pivot/Unpivot Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Use Python to inspect database views and files
python3 << 'PYEOF'
import oracledb
import json
import os
import glob
import csv

result = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "views": {},
    "files": {},
    "source_tables_intact": False
}

# 1. Inspect Database Views
try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Check source tables
    cursor.execute("SELECT COUNT(*) FROM quarterly_costs")
    qc_count = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM annual_summary_wide")
    asw_count = cursor.fetchone()[0]
    result["source_tables_intact"] = (qc_count > 0 and asw_count > 0)

    # Check Views
    view_names = ["DEPT_JOB_SALARY_PIVOT", "QUARTERLY_SPENDING_PIVOT", "ANNUAL_COSTS_NORMALIZED"]
    
    for v_name in view_names:
        view_info = {"exists": False, "text": "", "columns": [], "row_count": 0, "sample_data": []}
        
        # Check existence and definition
        cursor.execute("SELECT text FROM user_views WHERE view_name = :1", [v_name])
        row = cursor.fetchone()
        if row:
            view_info["exists"] = True
            # View text is a LOB, read it
            view_info["text"] = str(row[0]) if row[0] else ""
        
        # Get columns if exists
        if view_info["exists"]:
            try:
                cursor.execute(f"SELECT * FROM {v_name} FETCH FIRST 5 ROWS ONLY")
                view_info["columns"] = [d[0] for d in cursor.description]
                rows = cursor.fetchall()
                view_info["sample_data"] = [list(r) for r in rows]
                
                cursor.execute(f"SELECT COUNT(*) FROM {v_name}")
                view_info["row_count"] = cursor.fetchone()[0]
            except Exception as e:
                view_info["error"] = str(e)
        
        result["views"][v_name] = view_info

    conn.close()
except Exception as e:
    result["db_error"] = str(e)

# 2. Inspect Export Files
expected_files = {
    "DEPT_JOB_SALARY_PIVOT": "/home/ga/Desktop/dept_job_salary_pivot.csv",
    "QUARTERLY_SPENDING_PIVOT": "/home/ga/Desktop/quarterly_spending_report.csv",
    "ANNUAL_COSTS_NORMALIZED": "/home/ga/Desktop/annual_costs_normalized.csv"
}

for key, fpath in expected_files.items():
    file_info = {"exists": False, "size": 0, "created_during_task": False, "content_preview": ""}
    if os.path.exists(fpath):
        file_info["exists"] = True
        stat = os.stat(fpath)
        file_info["size"] = stat.st_size
        file_info["created_during_task"] = (stat.st_mtime > result["task_start"])
        
        try:
            with open(fpath, 'r', errors='replace') as f:
                file_info["content_preview"] = f.read(500)
        except:
            pass
            
    result["files"][key] = file_info

# Save result
with open("/tmp/pivot_task_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print("Result exported to /tmp/pivot_task_result.json")
PYEOF

# Move to safe location if needed (though Python script wrote to /tmp)
chmod 666 /tmp/pivot_task_result.json 2>/dev/null || true

echo "=== Export Complete ==="