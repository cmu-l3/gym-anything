#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Optimize Data Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/sales_pipeline"
RESULT_FILE="/tmp/pipeline_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Run the pipeline to ensure outputs are fresh and check for syntax/runtime errors
echo "Running agent's modified pipeline..."
su - ga -c "cd $WORKSPACE_DIR && timeout 60 python3 run_pipeline.py > /tmp/agent_pipeline_run.log 2>&1" || echo "Pipeline failed or timed out" > /tmp/agent_pipeline_error.log

# Collect data via Python script
python3 << PYEXPORT
import json
import os
import stat

workspace = "$WORKSPACE_DIR"
gt_dir = "/var/lib/pipeline_ground_truth"
task_start = int("$TASK_START")

files_to_export = [
    "pipeline/data_loader.py",
    "pipeline/sales_aggregator.py",
    "pipeline/invoice_matcher.py",
    "pipeline/report_builder.py",
    "pipeline/trend_calculator.py"
]

outputs_to_export = [
    "department_summary.csv",
    "matched_invoices.csv",
    "trends.csv",
    "sales_report.txt"
]

result = {
    "source_code": {},
    "file_modified_after_start": {},
    "outputs": {},
    "ground_truth": {},
    "pipeline_run_log": ""
}

# 1. Read source code and modification times
for rel_path in files_to_export:
    path = os.path.join(workspace, rel_path)
    try:
        with open(path, "r", encoding="utf-8") as f:
            result["source_code"][rel_path] = f.read()
        
        mtime = os.stat(path).st_mtime
        result["file_modified_after_start"][rel_path] = (mtime > task_start)
    except Exception as e:
        result["source_code"][rel_path] = f"ERROR: {e}"
        result["file_modified_after_start"][rel_path] = False

# 2. Read agent outputs
for out_file in outputs_to_export:
    path = os.path.join(workspace, "output", out_file)
    try:
        with open(path, "r", encoding="utf-8") as f:
            result["outputs"][out_file] = f.read()
    except Exception as e:
        result["outputs"][out_file] = None

# 3. Read ground truth outputs
for out_file in outputs_to_export:
    path = os.path.join(gt_dir, out_file)
    try:
        with open(path, "r", encoding="utf-8") as f:
            result["ground_truth"][out_file] = f.read()
    except Exception as e:
        result["ground_truth"][out_file] = None

# 4. Read execution log
try:
    with open("/tmp/agent_pipeline_run.log", "r") as f:
        result["pipeline_run_log"] = f.read()
except:
    try:
        with open("/tmp/agent_pipeline_error.log", "r") as f:
            result["pipeline_run_log"] = f.read()
    except:
        result["pipeline_run_log"] = "Failed to run"

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported data to $RESULT_FILE")
PYEXPORT

sudo chmod 666 "$RESULT_FILE"
echo "=== Export Complete ==="