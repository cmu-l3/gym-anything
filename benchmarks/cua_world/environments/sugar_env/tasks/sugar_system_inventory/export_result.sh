#!/bin/bash
echo "=== Exporting sugar_system_inventory task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot as evidence
su - ga -c "$SUGAR_ENV scrot /tmp/inventory_task_end.png" 2>/dev/null || true

# Use Python to safely gather, parse, and package file attributes and contents into JSON format
python3 << 'PYEOF' > /tmp/inventory_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/inventory_analysis.json
import json
import os
import stat

result = {
    "script_exists": False,
    "script_executable": False,
    "script_size": 0,
    "script_content": "",
    "report_exists": False,
    "report_size": 0,
    "report_mtime": 0,
    "report_content": "",
    "task_start_ts": 0,
    "actual_activities": []
}

# Fetch task start timestamp
try:
    with open('/tmp/sugar_system_inventory_start_ts', 'r') as f:
        result["task_start_ts"] = int(f.read().strip())
except:
    pass

# Check agent's script file
script_path = '/home/ga/Documents/inventory.sh'
if os.path.exists(script_path):
    result["script_exists"] = True
    st = os.stat(script_path)
    result["script_size"] = st.st_size
    result["script_executable"] = bool(st.st_mode & stat.S_IXUSR)  # Executable by owner
    try:
        with open(script_path, 'r', encoding='utf-8', errors='replace') as f:
            result["script_content"] = f.read()
    except:
        pass

# Check agent's generated report
report_path = '/home/ga/Documents/system_report.txt'
if os.path.exists(report_path):
    result["report_exists"] = True
    st = os.stat(report_path)
    result["report_size"] = st.st_size
    result["report_mtime"] = int(st.st_mtime)
    try:
        with open(report_path, 'r', encoding='utf-8', errors='replace') as f:
            result["report_content"] = f.read()
    except:
        pass

# Fetch actual installed Sugar activities dynamically to establish ground truth
activities_dir = '/usr/share/sugar/activities'
if os.path.exists(activities_dir):
    try:
        activities = [d for d in os.listdir(activities_dir) if d.endswith('.activity')]
        result["actual_activities"] = activities
    except:
        pass

print(json.dumps(result))
PYEOF

chmod 666 /tmp/inventory_analysis.json
echo "Result packaged to /tmp/inventory_analysis.json"
echo "=== Export complete ==="