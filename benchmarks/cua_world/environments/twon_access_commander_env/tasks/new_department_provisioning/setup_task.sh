#!/bin/bash
echo "=== Setting up new_department_provisioning task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# -------------------------------------------------------
# Ensure clean slate:
#   - Remove any pre-existing "Executive Operations" group
#   - Remove any pre-existing "Executive Hours" time profile
#   - Remove any pre-existing Elena Vasquez user
# -------------------------------------------------------

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

# Remove Executive Operations group if exists
groups = ac("GET", "/groups")
if isinstance(groups, list):
    for g in groups:
        if g.get("name") == "Executive Operations":
            resp = ac("DELETE", f"/groups/{g['id']}")
            print(f"  Removed pre-existing 'Executive Operations' group (id={g['id']})")

# Remove Executive Hours time profile if exists
for endpoint in ["/timeProfiles", "/time-profiles"]:
    profiles = ac("GET", endpoint)
    if isinstance(profiles, list):
        for p in profiles:
            if p.get("name") == "Executive Hours":
                ac("DELETE", f"{endpoint}/{p['id']}")
                print(f"  Removed pre-existing 'Executive Hours' time profile")
        break

# Remove Elena Vasquez if exists
users = ac("GET", "/users")
if isinstance(users, list):
    for u in users:
        if u.get("firstName") == "Elena" and u.get("lastName") == "Vasquez":
            ac("DELETE", f"/users/{u['id']}")
            print(f"  Removed pre-existing Elena Vasquez (id={u['id']})")

# Verify IT Department exists with its correct members
all_groups = ac("GET", "/groups")
it_group = next((g for g in (all_groups or []) if g.get("name") == "IT Department"), None)
if it_group:
    members_resp = ac("GET", f"/groups/{it_group['id']}/members")
    print(f"  IT Department group id={it_group['id']}, members response type: {type(members_resp)}")
else:
    print("  WARNING: IT Department group not found — seeding may be incomplete")

print("new_department_provisioning setup complete")
PYEOF

# Navigate to Groups page to give agent a starting view
launch_firefox_to "${AC_URL}/#/groups" 8
take_screenshot /tmp/new_department_provisioning_start.png
echo "=== new_department_provisioning setup complete ==="
