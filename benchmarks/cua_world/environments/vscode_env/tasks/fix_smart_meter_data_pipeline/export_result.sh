#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Smart Meter Data Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/smart_meter_pipeline"
RESULT_FILE="/tmp/smart_meter_result.json"

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Remove any stale result file
rm -f "$RESULT_FILE"

# Collect all relevant source files into a single JSON dict
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"

files_to_export = {
    "data_loader.py":       os.path.join(workspace, "data_loader.py"),
    "cleaner.py":           os.path.join(workspace, "cleaner.py"),
    "aggregator.py":        os.path.join(workspace, "aggregator.py"),
    "tariff_calculator.py": os.path.join(workspace, "tariff_calculator.py"),
    "anomaly_detector.py":  os.path.join(workspace, "anomaly_detector.py"),
}

result = {}
for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        mtime = os.path.getmtime(path)
        result[label] = {"content": content, "mtime": mtime}
    except FileNotFoundError:
        result[label] = {"content": None, "mtime": 0}
        print(f"Warning: {path} not found")
    except Exception as e:
        result[label] = {"content": None, "mtime": 0}
        print(f"Warning: error reading {path}: {e}")

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported files to $RESULT_FILE")
PYEXPORT

echo "=== Export Complete ==="
ls -la "$RESULT_FILE" 2>/dev/null || echo "Warning: result file not created"