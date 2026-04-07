#!/bin/bash
echo "=== Exporting DB Retention Script Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual verification
take_screenshot /tmp/task_final.png

# Run python script to collect data and write to JSON safely
python3 << 'EOF'
import json
import os
import subprocess

result = {
    "script_exists": False,
    "script_executable": False,
    "created_during_task": False,
    "script_content": "",
    "test_exit_code": 999,
    "test_output": ""
}

script_path = "/home/ga/scripts/cleanup_events.sh"

try:
    with open("/tmp/task_start_time.txt", "r") as f:
        task_start = int(f.read().strip())
except:
    task_start = 0

if os.path.exists(script_path):
    result["script_exists"] = True
    result["script_executable"] = os.access(script_path, os.X_OK)
    
    # Anti-gaming: Ensure file was modified after task start
    mtime = os.stat(script_path).st_mtime
    if mtime > task_start:
        result["created_during_task"] = True
        
    try:
        with open(script_path, "r", encoding="utf-8", errors="ignore") as f:
            result["script_content"] = f.read()
    except Exception as e:
        result["script_content"] = f"Error reading file: {e}"
        
    # Programmatic check: Test script execution independently
    try:
        # Run as user 'ga' in a clean bash shell with timeout
        cmd = f"su - ga -c 'timeout 15 bash {script_path}'"
        proc = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        result["test_exit_code"] = proc.returncode
        result["test_output"] = proc.stdout + "\n" + proc.stderr
    except Exception as e:
        result["test_output"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

# Ensure the verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Exported Result:"
cat /tmp/task_result.json
echo "=== Export complete ==="