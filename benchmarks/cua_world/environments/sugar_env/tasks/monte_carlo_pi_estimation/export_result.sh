#!/bin/bash
echo "=== Exporting monte_carlo_pi_estimation task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/pi_task_end.png" 2>/dev/null || true

# We use Python here to safely serialize the agent's code and report text without quoting/escaping bash issues
python3 << 'PYEOF' > /tmp/pi_estimation_result.json
import json
import os

res = {
    "code_exists": False,
    "report_exists": False,
    "code_content": "",
    "report_content": "",
    "code_mtime": 0,
    "report_mtime": 0,
    "task_start": 0
}

try:
    with open('/tmp/pi_task_start_ts', 'r') as f:
        res["task_start"] = int(f.read().strip())
except Exception:
    pass

code_path = "/home/ga/Documents/math_projects/estimate_pi.py"
report_path = "/home/ga/Documents/math_projects/pi_report.txt"

if os.path.exists(code_path):
    res["code_exists"] = True
    res["code_mtime"] = os.path.getmtime(code_path)
    try:
        with open(code_path, 'r', errors='replace') as f:
            res["code_content"] = f.read()
    except Exception:
        pass

if os.path.exists(report_path):
    res["report_exists"] = True
    res["report_mtime"] = os.path.getmtime(report_path)
    try:
        with open(report_path, 'r', errors='replace') as f:
            res["report_content"] = f.read()
    except Exception:
        pass

print(json.dumps(res))
PYEOF

chmod 666 /tmp/pi_estimation_result.json
echo "Result safely exported to /tmp/pi_estimation_result.json"
echo "=== Export complete ==="