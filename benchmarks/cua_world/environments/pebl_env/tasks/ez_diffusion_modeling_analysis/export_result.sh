#!/bin/bash
echo "=== Exporting EZ-Diffusion Modeling Analysis Result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/ez_diffusion_final.png 2>/dev/null || true

# Combine results safely using python to avoid bash JSON parsing issues
python3 << 'PYEOF'
import json
import os

task_start = 0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = int(f.read().strip())
except:
    pass

file_path = "/home/ga/pebl/analysis/ez_diffusion_report.json"
file_created = False
if os.path.exists(file_path):
    mtime = os.stat(file_path).st_mtime
    if mtime >= task_start:
        file_created = True

res = {
    "output_exists": os.path.exists(file_path),
    "file_created_during_task": file_created
}

try:
    with open(file_path) as f:
        res["agent_report"] = json.load(f)
except Exception as e:
    res["agent_report"] = None
    res["agent_report_error"] = str(e)

try:
    with open("/tmp/ez_gt.json") as f:
        res["ground_truth"] = json.load(f)
except Exception as e:
    res["ground_truth"] = None

with open("/tmp/task_result.json", "w") as f:
    json.dump(res, f)
PYEOF

chmod 666 /tmp/task_result.json

echo "=== Export complete ==="