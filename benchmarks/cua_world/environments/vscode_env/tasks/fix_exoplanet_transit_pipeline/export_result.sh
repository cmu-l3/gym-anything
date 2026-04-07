#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Exoplanet Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/exoplanet_pipeline"
RESULT_FILE="/tmp/exoplanet_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run the pipeline locally to ensure output JSON is fresh based on agent's code
echo "Running agent's pipeline..."
cd "$WORKSPACE_DIR"
sudo -u ga python3 run_pipeline.py > /tmp/pipeline_stdout.log 2>&1 || true
sudo -u ga python3 -m pytest tests/ > /tmp/pytest_stdout.log 2>&1 || true

# 3. Collect source files and outputs into a single JSON
python3 << PYEXPORT
import json
import os
import stat

workspace = "$WORKSPACE_DIR"
result = {
    "task_start_time": $TASK_START,
    "pipeline_run_success": os.path.exists(os.path.join(workspace, "results/planet_parameters.json")),
    "pytest_output": open("/tmp/pytest_stdout.log").read() if os.path.exists("/tmp/pytest_stdout.log") else "",
    "pipeline_stdout": open("/tmp/pipeline_stdout.log").read() if os.path.exists("/tmp/pipeline_stdout.log") else "",
    "files": {}
}

files_to_export = [
    "pipeline/data_loader.py",
    "pipeline/detrender.py",
    "pipeline/outlier_rejection.py",
    "pipeline/transit_search.py",
    "pipeline/phase_folder.py",
    "results/planet_parameters.json"
]

for rel_path in files_to_export:
    full_path = os.path.join(workspace, rel_path)
    if os.path.exists(full_path):
        try:
            with open(full_path, "r", encoding="utf-8") as f:
                result["files"][rel_path] = f.read()
        except Exception as e:
            result["files"][rel_path] = f"ERROR reading: {e}"
    else:
        result["files"][rel_path] = None

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported data to $RESULT_FILE")
PYEXPORT

chmod 666 "$RESULT_FILE"
echo "=== Export Complete ==="