#!/bin/bash
set -e

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

echo "=== Exporting Task Results ==="

WORKSPACE_DIR="/home/ga/workspace/contract_parser"
TARGET_FILE="$WORKSPACE_DIR/contract_extractor.py"
RESULT_JSON="/tmp/task_result.json"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")

FILE_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Best-effort: focus VSCode and save all open files
if type focus_vscode_window &>/dev/null; then
    focus_vscode_window 2>/dev/null || true
    sleep 1
    if type safe_xdotool &>/dev/null; then
        safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
        sleep 1
    else
        su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+shift+s" 2>/dev/null || true
    fi
fi
sleep 2

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run evaluation script (runs both local and hidden tests)
cat > /tmp/evaluator.py << 'EVALEOF'
import json
import sys
import importlib.util
import os

results = {
    "syntax_error": False,
    "error_msg": "",
    "local_parties": False,
    "local_date": False,
    "local_law": False,
    "local_conf": False,
    "local_term": False,
    "hidden_parties": False,
    "hidden_date": False,
    "hidden_law": False,
    "hidden_conf": False,
    "hidden_term": False
}

target_path = "/home/ga/workspace/contract_parser/contract_extractor.py"

try:
    spec = importlib.util.spec_from_file_location("contract_extractor", target_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
except Exception as e:
    results["syntax_error"] = True
    results["error_msg"] = str(e)
    with open("/tmp/eval_output.json", "w") as f:
        json.dump(results, f)
    sys.exit(0)

# --- LOCAL TESTS ---
try:
    t = "This Agreement is made by and between Acme Corp and Beta LLC. This is another sentence. And another."
    if mod.extract_parties(t) == "Acme Corp and Beta LLC": results["local_parties"] = True
except: pass

try:
    t = "This instrument is dated this 1st day of October, 2021 by and between the undersigned."
    r = mod.extract_date(t)
    if r and "October" in r and "2021" in r: results["local_date"] = True
except: pass

try:
    t = "This Agreement shall be governed by and construed in accordance with the laws of the State of New York."
    r = mod.extract_governing_law(t)
    if r and "New York" in r: results["local_law"] = True
except: pass

try:
    t = '"Confidential Information" means all information disclosed by\nOne party to another that is marked confidential.'
    r = mod.extract_confidentiality(t)
    if r and "marked confidential" in r: results["local_conf"] = True
except: pass

try:
    t = "Either party may invoke termination\nfor convenience with 30 days written notice to the other party."
    if mod.extract_termination(t) is True: results["local_term"] = True
except: pass

# --- HIDDEN GENERALIZATION TESTS ---
try:
    t = "This Agreement is made by and between Global Industries, Inc. and Local Startup LLC. The parties agree to..."
    if mod.extract_parties(t) == "Global Industries, Inc. and Local Startup LLC": results["hidden_parties"] = True
except: pass

try:
    t = "This Agreement is made and entered into this 15th day of November, 2022 by and between..."
    r = mod.extract_date(t)
    if r and "November" in r and "2022" in r: results["hidden_date"] = True
except: pass

try:
    t = "This instrument and all disputes arising hereunder shall be governed by, and construed in accordance with, the internal laws of the State of California."
    r = mod.extract_governing_law(t)
    if r and "California" in r: results["hidden_law"] = True
except: pass

try:
    t = '"Confidential Information" means any proprietary material\nor trade secret\nthat is disclosed by the Disclosing Party.'
    r = mod.extract_confidentiality(t)
    if r and "disclosed by the Disclosing Party" in r: results["hidden_conf"] = True
except: pass

try:
    t = "The right of termination\r\nfor convenience may be exercised by the Buyer."
    if mod.extract_termination(t) is True: results["hidden_term"] = True
except: pass

with open("/tmp/eval_output.json", "w") as f:
    json.dump(results, f)
EVALEOF

python3 /tmp/evaluator.py

# Combine metadata and test results
cat > "$RESULT_JSON" << EOF
{
    "file_modified": $FILE_MODIFIED,
    "tests": $(cat /tmp/eval_output.json 2>/dev/null || echo "{}")
}
EOF

chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Export complete. Results saved to $RESULT_JSON"