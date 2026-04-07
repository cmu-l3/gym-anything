#!/bin/bash
echo "=== Exporting rd_department_onboarding result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot before any windows are closed
take_screenshot /tmp/task_final.png

# Use Python with requests for robust v3.5.2 API extraction
cat << 'EOF' > /tmp/export_data.py
import requests
import json
import urllib3
import os

urllib3.disable_warnings()

AC_URL = "https://localhost:9443"
AC_USER = "admin"
AC_PASS = "Admin2n1!"

s = requests.Session()
s.verify = False

result = {
    "zones": [],
    "rules": [],
    "groups": [],
    "profiles": [],
    "group_members": {},
    "user_details": {},
    "report_exists": False,
    "report_content": "",
    "report_created_after_start": False
}

def safe_get(endpoint):
    try:
        resp = s.get(f"{AC_URL}{endpoint}", timeout=10)
        if resp.status_code in (200, 201):
            data = resp.json()
            # v3.5.2 wraps lists in {items: [...], count: N}
            if isinstance(data, dict) and "items" in data:
                return data["items"]
            return data
    except:
        pass
    return []

try:
    s.put(f"{AC_URL}/api/v3/login",
          json={"login": AC_USER, "password": AC_PASS}, timeout=10)

    # Fetch all entity types
    result["zones"] = safe_get("/api/v3/zones")
    result["rules"] = safe_get("/api/v3/accessRules")
    result["groups"] = safe_get("/api/v3/groups")
    result["profiles"] = safe_get("/api/v3/timeProfiles")

    # Build group membership map from user Groups field
    all_users = safe_get("/api/v3/users")

    # Collect details for task-referenced users
    target_names = {
        "Amelia Chen", "Marcus Rivera",
        "Darnell Robinson",
        "Kwame Asante", "Mei-Ling Zhang",
    }

    for u in all_users:
        name = u.get("Name", "")
        if name in target_names:
            uid = u.get("Id")
            creds = u.get("AccessCredentials", {})
            groups = u.get("Groups", [])
            account = u.get("Account", {})

            result["user_details"][name] = {
                "id": uid,
                "Name": name,
                "email": account.get("Email", ""),
                "phone": account.get("Phone", ""),
                "company": u.get("Company", {}).get("Name", "") if isinstance(u.get("Company"), dict) else "",
                "enabled": not u.get("IsSuspended", False),
                "groups": [g.get("Name", "") for g in groups],
                "cards": creds.get("Cards", []),
                "pin": creds.get("Pin"),
                "credentials_raw": creds
            }

except Exception as e:
    result["error"] = str(e)

# Check report file
file_path = "/home/ga/Documents/rd_onboarding.txt"
if os.path.exists(file_path):
    result["report_exists"] = True
    with open(file_path, "r") as f:
        result["report_content"] = f.read()[:10000]

    mtime = os.path.getmtime(file_path)
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            start_time = float(f.read().strip())
        if mtime >= start_time:
            result["report_created_after_start"] = True
    except:
        result["report_created_after_start"] = True

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

python3 /tmp/export_data.py
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export complete ==="
