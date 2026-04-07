#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Financial Reconciliation Engine Result ==="

WORKSPACE_DIR="/home/ga/workspace/reconciliation_engine"
RESULT_FILE="/tmp/reconciliation_result.json"

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
    "engine/matcher.py":            os.path.join(workspace, "engine", "matcher.py"),
    "engine/fx_handler.py":         os.path.join(workspace, "engine", "fx_handler.py"),
    "engine/date_handler.py":       os.path.join(workspace, "engine", "date_handler.py"),
    "engine/tolerance_checker.py":  os.path.join(workspace, "engine", "tolerance_checker.py"),
    "engine/exception_reporter.py": os.path.join(workspace, "engine", "exception_reporter.py"),
    "config.py":                    os.path.join(workspace, "config.py"),
    "run_reconciliation.py":        os.path.join(workspace, "run_reconciliation.py"),
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

echo "=== Export Complete ==="
ls -la "$RESULT_FILE" 2>/dev/null || echo "Warning: result file not created"
