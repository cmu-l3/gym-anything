#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Epidemiological Data Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/surveillance_pipeline"
RESULT_FILE="/tmp/epidemiological_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1

echo "Saving all files..."
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
    "pipeline/data_loader.py": os.path.join(workspace, "pipeline", "data_loader.py"),
    "pipeline/metrics.py": os.path.join(workspace, "pipeline", "metrics.py"),
    "run_pipeline.py": os.path.join(workspace, "run_pipeline.py"),
    "tests/test_pipeline.py": os.path.join(workspace, "tests", "test_pipeline.py")
}

result = {}
for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result[label] = f.read()
    except FileNotFoundError:
        result[label] = None
        print(f"Warning: {path} not found")
    except Exception as e:
        result[label] = None
        print(f"Warning: error reading {path}: {e}")

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported {len([v for v in result.values() if v is not None])} files to $RESULT_FILE")
PYEXPORT

chmod 666 "$RESULT_FILE"

echo "=== Export Complete ==="