#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)

# Extract config files into a single JSON dump for the verifier
echo "Compiling config file states..."

python3 << 'PYEOF'
import json
import os
import time

services = ['user', 'feeds', 'publish', 'notification']
base_dir = '/opt/socioboard/socioboard-api/'

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = int(f.read().strip())
except:
    start_time = 0

result = {
    "task_start_time": start_time,
    "task_end_time": int(time.time()),
    "services": {}
}

for svc in services:
    path = os.path.join(base_dir, svc, 'config', 'development.json')
    svc_data = {
        "exists": False,
        "mtime": 0,
        "content": ""
    }
    
    if os.path.exists(path):
        svc_data["exists"] = True
        svc_data["mtime"] = int(os.path.getmtime(path))
        try:
            with open(path, 'r') as f:
                svc_data["content"] = f.read()
        except Exception as e:
            svc_data["content"] = f"ERROR_READING_FILE: {e}"
            
    result["services"][svc] = svc_data

# Save to temp file and move with safe permissions
tmp_path = '/tmp/result_tmp.json'
with open(tmp_path, 'w') as f:
    json.dump(result, f)

PYEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_tmp.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/result_tmp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/result_tmp.json

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="