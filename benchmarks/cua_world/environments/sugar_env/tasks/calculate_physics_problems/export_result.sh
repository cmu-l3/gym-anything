#!/bin/bash
# Do NOT use set -e
echo "=== Exporting calculate_physics_problems task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/physics_task_end.png" 2>/dev/null || true

python3 << 'PYEOF' > /tmp/physics_result.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/physics_result.json
import json
import os

result = {
    "file_exists": False,
    "file_size": 0,
    "file_modified": False,
    "content": ""
}

filepath = "/home/ga/Documents/physics_answers.txt"
if os.path.exists(filepath):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(filepath)
    
    start_time = 0
    try:
        with open("/tmp/physics_answers_start_ts", "r") as f:
            start_time = int(f.read().strip())
    except:
        pass
        
    if os.path.getmtime(filepath) > start_time:
        result["file_modified"] = True
        
    try:
        with open(filepath, "r", encoding="utf-8", errors="replace") as f:
            result["content"] = f.read()
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

chmod 666 /tmp/physics_result.json
echo "Result saved to /tmp/physics_result.json"
cat /tmp/physics_result.json
echo "=== Export complete ==="