#!/bin/bash
echo "=== Exporting sugar_codebase_metrics task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/sugar_metrics_task_end.png" 2>/dev/null || true

# Compute ground truth and gather results using Python
python3 << 'PYEOF' > /tmp/sugar_codebase_metrics_result.json
import json
import os
import stat
import time

result = {
    "script_exists": False,
    "script_executable": False,
    "csv_exists": False,
    "csv_content": "",
    "ground_truth": {},
    "mystery_activity": "Mystery.activity"
}

script_path = "/home/ga/Documents/analyze_activities.sh"
csv_path = "/home/ga/Documents/sugar_metrics.csv"

if os.path.exists(script_path):
    result["script_exists"] = True
    st = os.stat(script_path)
    result["script_executable"] = bool(st.st_mode & stat.S_IXUSR) or bool(st.st_mode & stat.S_IXGRP) or bool(st.st_mode & stat.S_IXOTH)
    
if os.path.exists(csv_path):
    result["csv_exists"] = True
    try:
        with open(csv_path, "r", encoding="utf-8", errors="ignore") as f:
            result["csv_content"] = f.read()
    except Exception:
        pass

base_dir = '/usr/share/sugar/activities'
if os.path.exists(base_dir):
    for act in os.listdir(base_dir):
        if act.endswith('.activity'):
            act_path = os.path.join(base_dir, act)
            if os.path.isdir(act_path):
                py_files = []
                for root, dirs, files in os.walk(act_path):
                    for f in files:
                        if f.endswith('.py'):
                            py_files.append(os.path.join(root, f))
                
                if len(py_files) > 0:
                    total_loc = 0
                    for pf in py_files:
                        try:
                            with open(pf, 'rb') as f:
                                content = f.read()
                                # Count newlines to perfectly match `wc -l` behavior
                                total_loc += content.count(b'\n')
                        except Exception:
                            pass
                    result["ground_truth"][act] = {'py_files': len(py_files), 'total_loc': total_loc}

print(json.dumps(result))
PYEOF

chmod 666 /tmp/sugar_codebase_metrics_result.json
echo "Result saved to /tmp/sugar_codebase_metrics_result.json"
echo "=== Export complete ==="