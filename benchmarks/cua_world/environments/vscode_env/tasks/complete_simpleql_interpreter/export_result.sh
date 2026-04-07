#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Complete SimpleQL Interpreter Result ==="

WORKSPACE_DIR="/home/ga/workspace/simpleql"
RESULT_DIR="/tmp/simpleql_results"
mkdir -p "$RESULT_DIR"

# Focus VS Code and save files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 2

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Capture current checksums
echo -n "" > "$RESULT_DIR/final_checksums.txt"
for f in lexer.py parser.py evaluator.py; do
    if [ -f "$WORKSPACE_DIR/$f" ]; then
        md5sum "$WORKSPACE_DIR/$f" >> "$RESULT_DIR/final_checksums.txt"
    fi
done

# 2. Run Test Suite (Primary)
cd "$WORKSPACE_DIR"
export SIMPLEQL_TEST_REPORT="$RESULT_DIR/primary_report.json"
sudo -u ga python3 test_simpleql.py || true

# 3. Run Test Suite (Verification/Hidden)
export SIMPLEQL_TEST_REPORT="$RESULT_DIR/hidden_report.json"
# (Since the test suite uses hardcoded data dicts in the test file, 
# running the suite twice serves to ensure their code works against the test suite.
# For true hidden data, we verify the code logic itself in verifier.py)
sudo -u ga python3 test_simpleql.py || true

# 4. Copy source files for verifier syntax analysis
for f in lexer.py parser.py evaluator.py; do
    if [ -f "$WORKSPACE_DIR/$f" ]; then
        cp "$WORKSPACE_DIR/$f" "$RESULT_DIR/"
    fi
done

# 5. Pack into single result JSON
python3 << 'PYEOF'
import json, os

res_dir = "/tmp/simpleql_results"
result = {"tests": {}, "files": {}, "checksums": {}}

# Read reports
for report_name in ["primary_report.json", "hidden_report.json"]:
    path = os.path.join(res_dir, report_name)
    if os.path.exists(path):
        with open(path) as f:
            result["tests"][report_name] = json.load(f)

# Read files
for fname in ["lexer.py", "parser.py", "evaluator.py"]:
    path = os.path.join(res_dir, fname)
    if os.path.exists(path):
        with open(path) as f:
            result["files"][fname] = f.read()

# Read initial checksums
try:
    with open("/tmp/simpleql_initial_checksums.txt") as f:
        result["checksums"]["initial"] = f.read().strip()
except:
    pass

# Read final checksums
try:
    with open(os.path.join(res_dir, "final_checksums.txt")) as f:
        result["checksums"]["final"] = f.read().strip()
except:
    pass

with open("/tmp/simpleql_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/simpleql_result.json
echo "=== Export Complete ==="