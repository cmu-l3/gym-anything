#!/bin/bash
set -e

echo "=== Exporting swm_error_tracking result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Take final screenshot for VLM evidence if needed
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Prepare verification package by safely aggregating the agent output and the ground truth
python3 << 'EOF'
import json
import os

agent_file = "/home/ga/pebl/analysis/swm_report.json"
gt_file = "/var/lib/pebl/swm_gt.json"
start_timestamp_file = "/tmp/task_start_timestamp"

# Load Agent Report
try:
    with open(agent_file, "r") as f:
        agent_report = json.load(f)
except Exception:
    agent_report = None

# Load Ground Truth
try:
    with open(gt_file, "r") as f:
        gt = json.load(f)
except Exception:
    gt = None

# Check Anti-Gaming Timestamps
try:
    with open(start_timestamp_file, "r") as f:
        start_time = int(f.read().strip())
    file_mtime = int(os.path.getmtime(agent_file))
    created_during_task = file_mtime > start_time
except Exception:
    created_during_task = False

output_payload = {
    "agent_report": agent_report,
    "ground_truth": gt,
    "created_during_task": created_during_task
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(output_payload, f)
EOF

# Ensure appropriate permissions for copy_from_env
chmod 644 /tmp/task_result.json

echo "=== swm_error_tracking export complete ==="