#!/bin/bash
# Export script for Scheduler Compensation Automation task
# Queries database metadata and content to verify task completion

set -e
echo "=== Exporting Scheduler Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read start time for timestamp validation
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Run Python script to gather detailed verification data from Oracle
python3 << 'PYEOF'
import oracledb
import json
import os
import time

result = {
    "tables": {},
    "procedures": {},
    "jobs": {},
    "data": {},
    "files": {},
    "errors": []
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Verify Tables
    tables = ["COMPENSATION_SNAPSHOTS", "SALARY_ANOMALIES"]
    for table in tables:
        try:
            # Check existence
            cursor.execute("SELECT count(*) FROM user_tables WHERE table_name = :1", [table])
            exists = cursor.fetchone()[0] > 0
            
            row_count = 0
            columns = []
            
            if exists:
                # Get row count
                cursor.execute(f"SELECT count(*) FROM {table}")
                row_count = cursor.fetchone()[0]
                
                # Get columns
                cursor.execute("SELECT column_name FROM user_tab_columns WHERE table_name = :1", [table])
                columns = [row[0] for row in cursor.fetchall()]

            result["tables"][table] = {
                "exists": exists,
                "row_count": row_count,
                "columns": columns
            }
        except Exception as e:
            result["errors"].append(f"Table {table} error: {str(e)}")

    # 2. Verify Procedures
    procs = ["CAPTURE_COMP_SNAPSHOT", "DETECT_SALARY_ANOMALIES"]
    for proc in procs:
        try:
            cursor.execute("SELECT status FROM user_objects WHERE object_name = :1 AND object_type = 'PROCEDURE'", [proc])
            row = cursor.fetchone()
            result["procedures"][proc] = {
                "exists": row is not None,
                "status": row[0] if row else "MISSING"
            }
        except Exception as e:
            result["errors"].append(f"Proc {proc} error: {str(e)}")

    # 3. Verify Scheduler Jobs
    jobs = ["MONTHLY_COMP_SNAPSHOT", "DAILY_ANOMALY_CHECK"]
    for job in jobs:
        try:
            # Check job definition
            cursor.execute("""
                SELECT state, repeat_interval, job_action, job_type 
                FROM user_scheduler_jobs 
                WHERE job_name = :1
            """, [job])
            row = cursor.fetchone()
            
            job_info = {
                "exists": row is not None,
                "state": row[0] if row else "MISSING",
                "interval": row[1] if row else "",
                "action": row[2] if row else "",
                "type": row[3] if row else ""
            }
            
            # Check execution history (did it run?)
            cursor.execute("""
                SELECT count(*) 
                FROM user_scheduler_job_run_details 
                WHERE job_name = :1 AND status = 'SUCCEEDED'
            """, [job])
            run_count = cursor.fetchone()[0]
            job_info["run_count"] = run_count
            
            result["jobs"][job] = job_info
            
        except Exception as e:
            result["errors"].append(f"Job {job} error: {str(e)}")

    # 4. Verify Data Quality (Sample checks)
    if result["tables"]["SALARY_ANOMALIES"]["exists"]:
        try:
            # Check for valid anomaly types
            cursor.execute("SELECT count(*) FROM SALARY_ANOMALIES WHERE anomaly_type NOT IN ('ABOVE_RANGE', 'BELOW_RANGE')")
            invalid_types = cursor.fetchone()[0]
            
            # Check calculation logic (sample one record if exists)
            cursor.execute("SELECT deviation_pct, salary, dept_avg_salary FROM SALARY_ANOMALIES FETCH FIRST 1 ROWS ONLY")
            sample = cursor.fetchone()
            sample_valid = False
            if sample:
                dev, sal, avg = sample
                # Verify deviation calculation roughly matches: ((sal - avg) / avg) * 100
                if avg and avg > 0:
                    calc_dev = ((sal - avg) / avg) * 100
                    if abs(calc_dev - dev) < 1.0: # 1% tolerance
                        sample_valid = True
            
            result["data"]["anomalies"] = {
                "invalid_types": invalid_types,
                "sample_calculation_valid": sample_valid
            }
        except Exception as e:
            result["errors"].append(f"Data verification error: {str(e)}")

except Exception as e:
    result["errors"].append(f"Global DB error: {str(e)}")
finally:
    if 'conn' in locals(): conn.close()

# 5. Verify Export Files
files = [
    "/home/ga/Desktop/compensation_snapshots.csv",
    "/home/ga/Desktop/salary_anomalies.csv"
]
for fpath in files:
    fname = os.path.basename(fpath)
    exists = os.path.exists(fpath)
    size = os.path.getsize(fpath) if exists else 0
    mtime = os.path.getmtime(fpath) if exists else 0
    
    result["files"][fname] = {
        "exists": exists,
        "size": size,
        "mtime": mtime
    }

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Ensure result file permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json