#!/bin/bash
echo "=== Exporting joint_wear_maintenance_profiling Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
TRACE_CSV="/home/ga/Documents/CoppeliaSim/exports/trajectory_trace.csv"
WEAR_CSV="/home/ga/Documents/CoppeliaSim/exports/joint_wear_log.csv"
SCHEDULE_JSON="/home/ga/Documents/CoppeliaSim/exports/maintenance_schedule.json"

take_screenshot /tmp/task_final.png

# Process files via Python to avoid bash parsing complexities
python3 << PYEOF > /tmp/task_result.json
import json
import os
import csv

task_start = $TASK_START
trace_csv = "$TRACE_CSV"
wear_csv = "$WEAR_CSV"
schedule_json = "$SCHEDULE_JSON"

result = {
    "task_start": task_start,
    "trace_exists": False,
    "trace_is_new": False,
    "trace_rows": 0,
    "wear_exists": False,
    "wear_is_new": False,
    "wear_rows": 0,
    "schedule_exists": False,
    "schedule_is_new": False,
    "schedule_valid": False,
    "critical_travel_joint": -1,
    "j0_annual_travel": 0.0,
    "j5_annual_travel": 0.0
}

# 1. Trace CSV
if os.path.isfile(trace_csv):
    result["trace_exists"] = True
    mtime = os.path.getmtime(trace_csv)
    if mtime > task_start:
        result["trace_is_new"] = True
    try:
        with open(trace_csv, 'r') as f:
            reader = csv.reader(f)
            rows = list(reader)
            if len(rows) > 0:
                result["trace_rows"] = len(rows) - 1  # Excluding header
    except:
        pass

# 2. Wear Log CSV
if os.path.isfile(wear_csv):
    result["wear_exists"] = True
    mtime = os.path.getmtime(wear_csv)
    if mtime > task_start:
        result["wear_is_new"] = True
    try:
        with open(wear_csv, 'r') as f:
            reader = csv.reader(f)
            rows = list(reader)
            # Count data rows (excluding headers if present)
            data_rows = [r for r in rows if len(r) > 0 and r[0].strip().isdigit()]
            result["wear_rows"] = len(data_rows)
    except:
        pass

# 3. Schedule JSON
if os.path.isfile(schedule_json):
    result["schedule_exists"] = True
    mtime = os.path.getmtime(schedule_json)
    if mtime > task_start:
        result["schedule_is_new"] = True
    try:
        with open(schedule_json, 'r') as f:
            data = json.load(f)
        
        required_keys = ["simulated_cycles", "annual_cycles", "wear_summary", "critical_travel_joint", "critical_reversal_joint"]
        if all(k in data for k in required_keys) and isinstance(data["wear_summary"], list):
            result["schedule_valid"] = True
            result["critical_travel_joint"] = int(data["critical_travel_joint"])
            
            # Extract J0 and J5 annual travel for physics verification
            for ws in data["wear_summary"]:
                if str(ws.get("joint_idx")) == "0":
                    result["j0_annual_travel"] = float(ws.get("annual_travel_rad", 0.0))
                elif str(ws.get("joint_idx")) == "5":
                    result["j5_annual_travel"] = float(ws.get("annual_travel_rad", 0.0))
    except Exception as e:
        print("Error parsing schedule_json:", e)

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json