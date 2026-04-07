#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

WORKSPACE="/home/ga/workspace/gcode_processor"
RESULT_FILE="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus VSCode and save all files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 2

# ──────────────────────────────────────────────────────────
# 1. Run Unit Tests
# ──────────────────────────────────────────────────────────
echo "Running pytest..."
cd "$WORKSPACE"
su - ga -c "cd $WORKSPACE && python3 -m pytest tests/ -v > /tmp/pytest.log 2>&1" || true

# ──────────────────────────────────────────────────────────
# 2. Run E2E Integration on Hidden Ground Truth
# ──────────────────────────────────────────────────────────
echo "Running E2E script on hidden ground truth data..."
su - ga -c "cd $WORKSPACE && python3 main.py /var/lib/app/ground_truth/complex_part.gcode /tmp/out.gcode > /tmp/e2e.log 2>&1" || true

# ──────────────────────────────────────────────────────────
# 3. Collect Data into JSON
# ──────────────────────────────────────────────────────────
python3 << 'EOF'
import json, os, re

# Parse pytest results
pytest_log = ""
try:
    with open('/tmp/pytest.log', 'r') as f:
        pytest_log = f.read()
except FileNotFoundError:
    pass

tests = {
    "test_comment_parsing": "FAILED",
    "test_positioning_modes": "FAILED",
    "test_arc_geometry": "FAILED",
    "test_modal_state": "FAILED",
    "test_number_formatting": "FAILED"
}

for t in tests.keys():
    if re.search(fr'{t}.py\s+PASSED', pytest_log) or re.search(fr'PASSED\s+tests/{t}.py', pytest_log):
        tests[t] = "PASSED"

# Parse E2E output
e2e_log = ""
estimated_time = -1.0
try:
    with open('/tmp/e2e.log', 'r') as f:
        e2e_log = f.read()
        match = re.search(r'Total estimated time:\s*([0-9.]+)', e2e_log)
        if match:
            estimated_time = float(match.group(1))
except FileNotFoundError:
    pass

# Check format of output file
has_scientific_notation = False
try:
    with open('/tmp/out.gcode', 'r') as f:
        content = f.read()
        if re.search(r'[eE][+-][0-9]+', content):
            has_scientific_notation = True
except FileNotFoundError:
    pass

result = {
    "tests": tests,
    "e2e": {
        "log": e2e_log,
        "estimated_time": estimated_time,
        "has_scientific_notation": has_scientific_notation,
        "output_exists": os.path.exists('/tmp/out.gcode')
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="