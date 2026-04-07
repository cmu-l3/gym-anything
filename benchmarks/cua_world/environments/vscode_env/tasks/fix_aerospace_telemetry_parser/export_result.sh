#!/bin/bash
set -e

echo "=== Exporting Aerospace Telemetry Parser Result ==="

WORKSPACE_DIR="/home/ga/workspace/telemetry_decoder"
RESULT_FILE="/tmp/telemetry_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus VSCode and save all files
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+s" 2>/dev/null || true
sleep 1

# Extract output metrics and package into JSON
python3 << PYEXPORT
import json
import os
import subprocess

workspace = "$WORKSPACE_DIR"
parser_path = os.path.join(workspace, "parser.py")
csv_path = os.path.join(workspace, "flight_trajectory.csv")

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "parser_code": "",
    "csv_exists": False,
    "csv_stats": {},
    "git_commits": []
}

# 1. Read parser.py
try:
    with open(parser_path, "r", encoding="utf-8") as f:
        result["parser_code"] = f.read()
except Exception as e:
    result["parser_code"] = f"ERROR: {e}"

# 2. Analyze CSV output if it exists
if os.path.exists(csv_path):
    result["csv_exists"] = True
    import csv
    try:
        with open(csv_path, "r") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            if rows:
                gps_rows = [r for r in rows if r['type'] == '1']
                imu_rows = [r for r in rows if r['type'] == '2']
                baro_rows = [r for r in rows if r['type'] == '3']
                status_rows = [r for r in rows if r['type'] == '4']
                
                if gps_rows:
                    result["csv_stats"]["avg_lat"] = sum(float(r['lat']) for r in gps_rows) / len(gps_rows)
                if imu_rows:
                    result["csv_stats"]["initial_az"] = float(imu_rows[0]['az'])
                if baro_rows:
                    result["csv_stats"]["max_pressure"] = max(float(r['pressure']) for r in baro_rows)
                if status_rows:
                    result["csv_stats"]["parachute_deployed_any"] = any(r['parachute_deployed'] == 'True' for r in status_rows)
    except Exception as e:
        result["csv_stats"]["error"] = str(e)

# 3. Get Git commits
try:
    git_log = subprocess.check_output(
        ["git", "log", "--oneline"], 
        cwd=workspace, 
        text=True
    ).strip().split('\n')
    result["git_commits"] = git_log
except Exception:
    pass

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported metrics to $RESULT_FILE")
PYEXPORT

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export Complete ==="