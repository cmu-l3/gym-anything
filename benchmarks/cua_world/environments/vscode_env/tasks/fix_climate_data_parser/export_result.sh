#!/bin/bash
set -e

echo "=== Exporting Climate Data Parser Result ==="
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# ─────────────────────────────────────────────────────────────
# 1. Run Hidden Evaluation Suite
# ─────────────────────────────────────────────────────────────
WORKSPACE_DIR="/home/ga/workspace/climate_parser"

rm -f /tmp/eval_results.json
# Run evaluation (needs sudo because ground_truth_eval is restricted)
sudo python3 /var/lib/app/ground_truth_eval/eval_tests.py "$WORKSPACE_DIR"

if [ ! -f "/tmp/eval_results.json" ]; then
    echo '{"error": "Evaluation script failed to produce results"}' > /tmp/eval_results.json
fi

# ─────────────────────────────────────────────────────────────
# 2. Extract modification timestamps
# ─────────────────────────────────────────────────────────────
LATEST_MTIME=0
for f in "$WORKSPACE_DIR/parser/"*.py; do
    if [ -f "$f" ]; then
        mtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$LATEST_MTIME" ]; then
            LATEST_MTIME=$mtime
        fi
    fi
done

FILE_MODIFIED_DURING_TASK="false"
if [ "$LATEST_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED_DURING_TASK="true"
fi

# ─────────────────────────────────────────────────────────────
# 3. Create JSON Result Export
# ─────────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << PYEXPORT
import json
import os

with open("/tmp/eval_results.json", "r") as f:
    eval_data = json.load(f)

export_data = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "latest_mtime": $LATEST_MTIME,
    "file_modified_during_task": "$FILE_MODIFIED_DURING_TASK" == "true",
    "eval_results": eval_data
}

with open("$TEMP_JSON", "w") as f:
    json.dump(export_data, f, indent=2)
PYEXPORT

# Move securely to the copy location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="