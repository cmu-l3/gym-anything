#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Debug React Dashboard Result ==="

WORKSPACE_DIR="/home/ga/workspace/ecommerce_dashboard"
RESULT_FILE="/tmp/react_dashboard_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

rm -f "$RESULT_FILE"

# Capture final screenshot for VLM verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Collect all modified files and their metadata
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"
task_start = int("$TASK_START")

files_to_export = [
    "src/components/LiveTicker.jsx",
    "src/components/OrderSearch.jsx",
    "src/components/MetricsChart.jsx",
    "src/components/ResponsiveContainer.jsx",
    "src/components/OrderList.jsx"
]

result = {
    "files": {},
    "metadata": {
        "task_start_time": task_start,
        "screenshot_exists": os.path.exists("/tmp/task_final.png")
    }
}

for rel_path in files_to_export:
    full_path = os.path.join(workspace, rel_path)
    file_data = {
        "content": None,
        "modified_during_task": False
    }
    
    try:
        if os.path.exists(full_path):
            with open(full_path, "r", encoding="utf-8") as f:
                file_data["content"] = f.read()
            mtime = os.path.getmtime(full_path)
            file_data["modified_during_task"] = mtime > task_start
    except Exception as e:
        file_data["error"] = str(e)
        
    result["files"][rel_path] = file_data

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)
PYEXPORT

chmod 666 "$RESULT_FILE"
echo "Exported files to $RESULT_FILE"
echo "=== Export Complete ==="