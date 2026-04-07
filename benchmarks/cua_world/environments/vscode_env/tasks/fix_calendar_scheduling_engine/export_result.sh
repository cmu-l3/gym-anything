#!/bin/bash
echo "=== Exporting Calendar Scheduling Engine Result ==="

source /workspace/scripts/task_utils.sh

WORKSPACE_DIR="/home/ga/workspace/calendar_engine"
RESULT_FILE="/tmp/calendar_result.json"

# Take final screenshot as evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

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
    "engine/recurrence.py":         os.path.join(workspace, "engine", "recurrence.py"),
    "engine/timezone_handler.py":   os.path.join(workspace, "engine", "timezone_handler.py"),
    "engine/event_model.py":        os.path.join(workspace, "engine", "event_model.py"),
    "engine/conflict_detector.py":  os.path.join(workspace, "engine", "conflict_detector.py"),
    "engine/ical_exporter.py":      os.path.join(workspace, "engine", "ical_exporter.py"),
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