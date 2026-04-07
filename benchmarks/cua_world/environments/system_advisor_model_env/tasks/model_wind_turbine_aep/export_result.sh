#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if Python was used to combat hardcoding/bypasses
export TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
export PYTHON_RAN="false"

if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Check if any .py files were created/modified and contain PySAM imports
PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null)
if [ -n "$PY_FILES" ]; then
    for pyf in $PY_FILES; do
        if grep -ql "import PySAM\|from PySAM\|Windpower" "$pyf" 2>/dev/null; then
            PYTHON_RAN="true"
            break
        fi
    done
fi

# Run an inline python script to safely parse and export the JSON output
python3 -c '
import json, os, sys

out = {
    "python_ran": os.environ.get("PYTHON_RAN") == "true",
    "file_exists": False,
    "file_modified": False,
    "parse_error": False,
    "data": {}
}

path = "/home/ga/Documents/SAM_Projects/wind_analysis_results.json"
task_start = int(os.environ.get("TASK_START", "0"))

if os.path.exists(path):
    out["file_exists"] = True
    mtime = os.path.getmtime(path)
    out["file_modified"] = mtime > task_start
    try:
        with open(path, "r") as f:
            data = json.load(f)
            if isinstance(data, dict):
                out["data"] = data
    except Exception as e:
        out["parse_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(out, f, indent=2)
'

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="