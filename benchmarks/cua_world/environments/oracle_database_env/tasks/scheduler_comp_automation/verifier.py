#!/usr/bin/env python3
"""
Verifier for Scheduler Compensation Automation task.

Scoring Criteria:
1. Tables exist (COMPENSATION_SNAPSHOTS, SALARY_ANOMALIES) - 10 pts
2. Procedures exist and are VALID - 16 pts
3. Scheduler jobs exist and are configured correctly - 20 pts
   - Correct repeat intervals (Monthly/Daily)
   - Correct job type/action
4. Tables contain data (Snapshot > 100 rows, Anomalies >= 1 row) - 20 pts
5. Jobs were executed successfully (Run count > 0) - 10 pts
6. Export CSV files exist on Desktop - 10 pts
7. Data quality checks (Columns correct, Anomaly logic valid) - 14 pts

Pass Threshold: 55 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scheduler_comp_automation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    tables = result.get("tables", {})
    procedures = result.get("procedures", {})
    jobs = result.get("jobs", {})
    files = result.get("files", {})
    data_quality = result.get("data", {}).get("anomalies", {})

    # 1. Verify Tables (10 pts)
    snap_table = tables.get("COMPENSATION_SNAPSHOTS", {})
    anom_table = tables.get("SALARY_ANOMALIES", {})
    
    if snap_table.get("exists"):
        score += 5
        feedback.append("Table COMPENSATION_SNAPSHOTS created.")
    else:
        feedback.append("Missing table COMPENSATION_SNAPSHOTS.")
        
    if anom_table.get("exists"):
        score += 5
        feedback.append("Table SALARY_ANOMALIES created.")
    else:
        feedback.append("Missing table SALARY_ANOMALIES.")

    # 2. Verify Procedures (16 pts)
    for proc_name in ["CAPTURE_COMP_SNAPSHOT", "DETECT_SALARY_ANOMALIES"]:
        proc = procedures.get(proc_name, {})
        if proc.get("exists"):
            if proc.get("status") == "VALID":
                score += 8
                feedback.append(f"Procedure {proc_name} is VALID.")
            else:
                score += 4
                feedback.append(f"Procedure {proc_name} exists but status is {proc.get('status')}.")
        else:
            feedback.append(f"Missing procedure {proc_name}.")

    # 3. Verify Jobs Configuration (20 pts)
    job_monthly = jobs.get("MONTHLY_COMP_SNAPSHOT", {})
    job_daily = jobs.get("DAILY_ANOMALY_CHECK", {})

    # Monthly Job
    if job_monthly.get("exists"):
        score += 3
        interval = job_monthly.get("interval", "").upper()
        if "MONTHLY" in interval:
            score += 7
            feedback.append("Monthly job configured correctly.")
        else:
            feedback.append(f"Monthly job interval incorrect: {interval}")
    else:
        feedback.append("Missing job MONTHLY_COMP_SNAPSHOT.")

    # Daily Job
    if job_daily.get("exists"):
        score += 3
        interval = job_daily.get("interval", "").upper()
        if "DAILY" in interval:
            score += 7
            feedback.append("Daily job configured correctly.")
        else:
            feedback.append(f"Daily job interval incorrect: {interval}")
    else:
        feedback.append("Missing job DAILY_ANOMALY_CHECK.")

    # 4. Verify Data Population (20 pts)
    snap_count = snap_table.get("row_count", 0)
    anom_count = anom_table.get("row_count", 0)

    if snap_count >= 100:
        score += 10
        feedback.append(f"Snapshots populated ({snap_count} rows).")
    elif snap_count > 0:
        score += 5
        feedback.append(f"Snapshots partially populated ({snap_count} rows).")
    else:
        feedback.append("COMPENSATION_SNAPSHOTS table is empty.")

    if anom_count >= 1:
        score += 10
        feedback.append(f"Anomalies populated ({anom_count} rows).")
    else:
        feedback.append("SALARY_ANOMALIES table is empty.")

    # 5. Verify Jobs Execution (10 pts)
    monthly_runs = job_monthly.get("run_count", 0)
    daily_runs = job_daily.get("run_count", 0)
    
    if monthly_runs > 0 and daily_runs > 0:
        score += 10
        feedback.append("Both scheduler jobs executed successfully.")
    elif monthly_runs > 0 or daily_runs > 0:
        score += 5
        feedback.append("Only one scheduler job executed.")
    else:
        feedback.append("No successful job execution history found.")

    # 6. Verify Export Files (10 pts)
    csv_snap = files.get("compensation_snapshots.csv", {})
    csv_anom = files.get("salary_anomalies.csv", {})
    
    if csv_snap.get("exists") and csv_snap.get("size", 0) > 100:
        score += 5
        feedback.append("Snapshot CSV export found.")
    
    if csv_anom.get("exists") and csv_anom.get("size", 0) > 0:
        score += 5
        feedback.append("Anomaly CSV export found.")

    # 7. Data Quality Checks (14 pts)
    # Check columns
    required_snap_cols = ["SNAPSHOT_DATE", "SALARY", "DEPARTMENT_NAME"]
    snap_cols = [c.upper() for c in snap_table.get("columns", [])]
    if all(req in snap_cols for req in required_snap_cols):
        score += 5
        feedback.append("Snapshot table structure correct.")
    
    required_anom_cols = ["DEVIATION_PCT", "ANOMALY_TYPE"]
    anom_cols = [c.upper() for c in anom_table.get("columns", [])]
    if all(req in anom_cols for req in required_anom_cols):
        score += 4
        feedback.append("Anomaly table structure correct.")

    # Check logic
    if data_quality.get("sample_calculation_valid"):
        score += 5
        feedback.append("Anomaly calculation logic verified.")
    
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }