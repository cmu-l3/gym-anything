#!/bin/bash
set -e
echo "=== Exporting Fix Broken Test Suite Result ==="

source /workspace/scripts/task_utils.sh

WORKSPACE_DIR="/home/ga/workspace/inventory_system"
RESULT_FILE="/tmp/test_suite_result.json"
HIDDEN_DIR="/var/lib/inventory_buggy"

# Focus VSCode and save all files
focus_vscode_window 2>/dev/null || true
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run evaluation script
cat > /tmp/run_eval.py << 'EOF'
import os
import json
import subprocess
import shutil

WORKSPACE = "/home/ga/workspace/inventory_system"
HIDDEN_DIR = "/var/lib/inventory_buggy"
START_TIME_FILE = "/tmp/task_start_time.txt"

def run_pytest(test_file=""):
    cmd = ["pytest", "-q", "--disable-warnings"]
    if test_file:
        cmd.append(test_file)
    result = subprocess.run(cmd, cwd=WORKSPACE, capture_output=True, text=True)
    return result.returncode == 0

# Get file modification times
with open(START_TIME_FILE, "r") as f:
    start_time = int(f.read().strip())

timestamps = {}
test_contents = {}

for t_file in os.listdir(os.path.join(WORKSPACE, "tests")):
    if t_file.endswith(".py"):
        path = os.path.join(WORKSPACE, "tests", t_file)
        timestamps[t_file] = int(os.path.getmtime(path))
        with open(path, "r") as f:
            test_contents[t_file] = f.read()

# 1. Run tests against CORRECT library
all_pass_correct = run_pytest()

# 2. Behavioral checks: Run specific tests against BUGGY variants
behavioral = {}

def swap_and_test(variant_dir, target_file, test_file, key):
    src = os.path.join(HIDDEN_DIR, variant_dir, target_file)
    dst = os.path.join(WORKSPACE, "inventory", target_file)
    bak = dst + ".bak"
    
    # Backup original
    shutil.copy2(dst, bak)
    # Put buggy in place
    shutil.copy2(src, dst)
    
    # Run test - we want it to FAIL against the buggy library
    # Return True if it correctly caught the bug (i.e. pytest failed)
    behavioral[key] = not run_pytest(f"tests/{test_file}")
    
    # Restore original
    shutil.move(bak, dst)

swap_and_test("variant1", "stock_manager.py", "test_stock_operations.py", "bug1_caught")
swap_and_test("variant2", "pricing.py", "test_pricing.py", "bug2_caught")
swap_and_test("variant3", "alerts.py", "test_alerts.py", "bug3_caught")
swap_and_test("variant4", "stock_manager.py", "test_transfers.py", "bug4_caught")
swap_and_test("variant5", "reports.py", "test_reports.py", "bug5_caught")
swap_and_test("variant6", "stock_manager.py", "test_concurrent_access.py", "bug6_caught")

# Compile final result
result = {
    "all_pass_correct": all_pass_correct,
    "behavioral": behavioral,
    "test_contents": test_contents,
    "timestamps": timestamps,
    "start_time": start_time
}

with open("/tmp/test_suite_result.json", "w") as f:
    json.dump(result, f, indent=2)

EOF

python3 /tmp/run_eval.py
chmod 666 /tmp/test_suite_result.json

echo "=== Export Complete ==="