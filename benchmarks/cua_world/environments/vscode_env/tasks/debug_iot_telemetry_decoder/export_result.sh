#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting IoT Telemetry Decoder Result ==="

WORKSPACE_DIR="/home/ga/workspace/iot_telemetry"
RESULT_FILE="/tmp/iot_telemetry_result.json"

# Best-effort: focus VSCode and trigger Save All (Ctrl+K, S)
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k s 2>/dev/null || true
sleep 2

# Take final screenshot
take_screenshot /tmp/task_final.png

rm -f "$RESULT_FILE"

# Collect all relevant source files into a single JSON dict for Verifier
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"

files_to_export = {
    "decoder.py":    os.path.join(workspace, "decoder.py"),
    "db_manager.py": os.path.join(workspace, "db_manager.py")
}

result = {}
for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result[label] = f.read()
    except Exception as e:
        result[label] = f"ERROR: {e}"

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported files to $RESULT_FILE")
PYEXPORT

echo "=== Export Complete ==="