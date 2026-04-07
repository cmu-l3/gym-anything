#!/bin/bash
echo "=== Exporting provision_cleaning_crew_access result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# We use a Python script to robustly export state via API to handle nested JSON accurately
cat << 'EOF' > /tmp/export_data.py
import requests
import json
import urllib3
import os

urllib3.disable_warnings()

AC_URL = "https://localhost:9443"
AC_USER = "admin"
AC_PASS = "2n"

s = requests.Session()
s.verify = False

result = {
    "time_profiles": [],
    "groups": [],
    "users": [],
    "cards": {},
    "file_exists": False,
    "file_content": "",
    "file_created_after_start": False
}

try:
    s.put(f"{AC_URL}/api/v3/auth", json={"login": AC_USER, "password": AC_PASS}, timeout=10)
    
    tp_resp = s.get(f"{AC_URL}/api/v3/timeProfiles", timeout=10)
    if tp_resp.status_code in (200, 201):
        result["time_profiles"] = tp_resp.json()
    else:
        tp_resp = s.get(f"{AC_URL}/api/v3/time-profiles", timeout=10)
        if tp_resp.status_code in (200, 201):
            result["time_profiles"] = tp_resp.json()
            
    g_resp = s.get(f"{AC_URL}/api/v3/groups", timeout=10)
    if g_resp.status_code in (200, 201):
        result["groups"] = g_resp.json()
        
    u_resp = s.get(f"{AC_URL}/api/v3/users", timeout=10)
    if u_resp.status_code in (200, 201):
        result["users"] = u_resp.json()
        
    for u in result["users"]:
        uid = u.get("id") or u.get("userId")
        if uid:
            c_resp = s.get(f"{AC_URL}/api/v3/users/{uid}/cards", timeout=10)
            if c_resp.status_code in (200, 201):
                result["cards"][str(uid)] = c_resp.json()
except Exception as e:
    result["error"] = str(e)

file_path = "/home/ga/Documents/cleaning_crew_setup.txt"
if os.path.exists(file_path):
    result["file_exists"] = True
    with open(file_path, "r") as f:
        result["file_content"] = f.read()
    
    mtime = os.path.getmtime(file_path)
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            start_time = float(f.read().strip())
        if mtime >= start_time:
            result["file_created_after_start"] = True
    except:
        result["file_created_after_start"] = True

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

python3 /tmp/export_data.py
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="