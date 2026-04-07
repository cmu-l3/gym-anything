#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Quant Backtest Bias Result ==="

WORKSPACE_DIR="/home/ga/workspace/quant_backtester"
RESULT_FILE="/tmp/quant_backtest_result.json"

# Take final screenshot BEFORE closing anything
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

# Package the backtest_engine.py into JSON for the verifier
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE_DIR"
target_file = os.path.join(workspace, "backtest_engine.py")

result = {
    "app_was_running": True if os.system("pgrep -f code > /dev/null") == 0 else False,
    "backtest_engine_code": None
}

try:
    with open(target_file, "r", encoding="utf-8") as f:
        result["backtest_engine_code"] = f.read()
except Exception as e:
    print(f"Warning: error reading {target_file}: {e}")

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)

print(f"Exported target file to $RESULT_FILE")
PYEXPORT

echo "=== Export Complete ==="