#!/bin/bash
echo "=== Exporting contractor_offboarding result ==="
source /workspace/scripts/task_utils.sh
ac_login

python3 << 'PYEOF'
import json, subprocess

ac_url = "https://localhost:9443"
cookie = "/tmp/ac_cookies.txt"

def ac(method, endpoint, body=None):
    cmd = ["curl", "-sk", "-b", cookie, "-c", cookie,
           "-X", method, "-H", "Content-Type: application/json",
           f"{ac_url}/api/v3{endpoint}"]
    if body:
        cmd += ["-d", json.dumps(body)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {}

all_users = ac("GET", "/users")
if not isinstance(all_users, list):
    all_users = []

meridian_users = []
non_meridian_users = []

for u in all_users:
    company = u.get("company", "")
    uid = u.get("id")
    if company == "Meridian Facilities":
        creds = ac("GET", f"/users/{uid}/credentials")
        if not isinstance(creds, list):
            creds = []
        meridian_users.append({
            "id": uid,
            "firstName": u.get("firstName"),
            "lastName": u.get("lastName"),
            "email": u.get("email", ""),
            "enabled": u.get("enabled", True),
            "credential_count": len(creds),
        })
    else:
        non_meridian_users.append({
            "id": uid,
            "firstName": u.get("firstName"),
            "lastName": u.get("lastName"),
            "email": u.get("email", ""),
            "enabled": u.get("enabled", True),
        })

result = {
    "meridian_users": meridian_users,
    "non_meridian_users": non_meridian_users,
    "meridian_count": len(meridian_users),
}

with open("/tmp/contractor_offboarding_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported: {len(meridian_users)} Meridian users, {len(non_meridian_users)} others")
PYEOF

echo "=== contractor_offboarding export complete ==="
