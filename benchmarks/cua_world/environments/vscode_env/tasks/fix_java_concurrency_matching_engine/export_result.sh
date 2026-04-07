#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Java Concurrency Result ==="

WORKSPACE="/home/ga/workspace/matching_engine"
RESULT_FILE="/tmp/task_result.json"

# Best-effort: save open files in VSCode
focus_vscode_window 2>/dev/null || true
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Take final screenshot
take_screenshot /tmp/task_final.png

# ──────────────────────────────────────────────────────────
# 1. Run the test suite against agent's code
# ──────────────────────────────────────────────────────────
echo "Running validation test suite..."
cd "$WORKSPACE"
RUN_LOG="/tmp/e2e_run.log"
RUN_EXIT_CODE=1

rm -rf bin/*
javac -d bin src/matching/*.java > /tmp/compile.log 2>&1
if [ $? -eq 0 ]; then
    # Run with a 15s timeout
    timeout 15s java -cp bin matching.Main > "$RUN_LOG" 2>&1
    RUN_EXIT_CODE=$?
else
    echo "Compilation failed during export." > "$RUN_LOG"
    cat /tmp/compile.log >> "$RUN_LOG"
fi

# ──────────────────────────────────────────────────────────
# 2. Collect files and results into JSON
# ──────────────────────────────────────────────────────────
python3 << PYEXPORT
import json, os

workspace = "$WORKSPACE"
log_file = "$RUN_LOG"

files_to_export = {
    "OrderProcessor.java":  os.path.join(workspace, "src/matching/OrderProcessor.java"),
    "MatchingEngine.java":  os.path.join(workspace, "src/matching/MatchingEngine.java"),
    "OrderBook.java":       os.path.join(workspace, "src/matching/OrderBook.java"),
    "BalanceTransfer.java": os.path.join(workspace, "src/matching/BalanceTransfer.java"),
    "MarketPublisher.java": os.path.join(workspace, "src/matching/MarketPublisher.java")
}

result = {
    "run_exit_code": $RUN_EXIT_CODE,
    "run_log": ""
}

try:
    with open(log_file, "r") as f:
        result["run_log"] = f.read()
except Exception:
    pass

for label, path in files_to_export.items():
    try:
        with open(path, "r", encoding="utf-8") as f:
            result[label] = f.read()
    except Exception as e:
        result[label] = ""

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(result, out, indent=2)
PYEXPORT

echo "Export complete to $RESULT_FILE"