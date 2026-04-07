#!/bin/bash
echo "=== Exporting meteorite_kml_generator task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/meteorite_task_end.png" 2>/dev/null || true

# Extract all relevant data using a Python script inside the container
# This avoids bash escaping nightmares and ensures robust JSON generation
python3 << 'PYEOF' > /tmp/meteorite_kml_result.json
import json
import os
import time

result = {
    "script_exists": False,
    "script_size": 0,
    "script_mtime": 0,
    "script_content": "",
    "kml_exists": False,
    "kml_size": 0,
    "kml_mtime": 0,
    "kml_content": "",
    "task_start_ts": 0
}

try:
    with open('/tmp/meteorite_kml_start_ts', 'r') as f:
        result["task_start_ts"] = int(f.read().strip())
except Exception:
    pass

script_path = '/home/ga/Documents/generate_kml.py'
kml_path = '/home/ga/Documents/massive_meteorites.kml'

if os.path.exists(script_path):
    result["script_exists"] = True
    result["script_size"] = os.path.getsize(script_path)
    result["script_mtime"] = os.path.getmtime(script_path)
    try:
        with open(script_path, 'r', encoding='utf-8', errors='replace') as f:
            result["script_content"] = f.read()[:50000]  # Cap at 50KB just in case
    except Exception:
        pass

if os.path.exists(kml_path):
    result["kml_exists"] = True
    result["kml_size"] = os.path.getsize(kml_path)
    result["kml_mtime"] = os.path.getmtime(kml_path)
    try:
        with open(kml_path, 'r', encoding='utf-8', errors='replace') as f:
            result["kml_content"] = f.read()[:50000]  # Cap at 50KB
    except Exception:
        pass

print(json.dumps(result))
PYEOF

chmod 666 /tmp/meteorite_kml_result.json
echo "Result successfully exported."
echo "=== Export complete ==="