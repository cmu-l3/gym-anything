#!/bin/bash
echo "=== Setting up group_membership_audit task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# -------------------------------------------------------
# Inject policy violations:
#   Olumide Adeyemi (Meridian Facilities) -> IT Department
#   Tomas Guerrero  (Meridian Facilities) -> Security Staff
#   Nadia Ivanova   (Meridian Facilities) -> Security Staff
#
# The seed script puts them only in "Contractors".
# This setup adds them to restricted groups to create violations.
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

all_users = ac("GET", "/users")
if not isinstance(all_users, list):
    all_users = []

all_groups = ac("GET", "/groups")
if not isinstance(all_groups, list):
    all_groups = []

def find_user(first, last):
    return next((u for u in all_users
                 if u.get("firstName") == first and u.get("lastName") == last), None)

def find_group(name):
    return next((g for g in all_groups if g.get("name") == name), None)

it_group     = find_group("IT Department")
sec_group    = find_group("Security Staff")
contractors_group = find_group("Contractors")

olumide = find_user("Olumide", "Adeyemi")
tomas   = find_user("Tomas", "Guerrero")
nadia   = find_user("Nadia", "Ivanova")

violations = [
    (olumide, it_group,  "Olumide Adeyemi -> IT Department"),
    (tomas,   sec_group, "Tomas Guerrero -> Security Staff"),
    (nadia,   sec_group, "Nadia Ivanova -> Security Staff"),
]

for user, group, label in violations:
    if user and group:
        uid = user["id"]
        gid = group["id"]
        resp = ac("POST", f"/groups/{gid}/members", {"userId": uid})
        print(f"  Injected violation: {label} — response: {json.dumps(resp)[:80]}")
    else:
        if not user:
            name = label.split("->")[0].strip()
            print(f"  WARNING: User '{name}' not found — seeding may be incomplete")
        if not group:
            grp_name = label.split("->")[1].strip()
            print(f"  WARNING: Group '{grp_name}' not found")

# Also ensure all 3 contractors are enabled and in the Contractors group
for user_spec in [("Nadia", "Ivanova"), ("Tomas", "Guerrero"), ("Olumide", "Adeyemi")]:
    u = find_user(*user_spec)
    if u:
        uid = u["id"]
        # Re-enable in case a prior task disabled them
        ac("PATCH", f"/users/{uid}", {"enabled": True})
        # Ensure in Contractors group
        if contractors_group:
            ac("POST", f"/groups/{contractors_group['id']}/members", {"userId": uid})
        print(f"  Reset {user_spec[0]} {user_spec[1]} to enabled, in Contractors group")

print("group_membership_audit setup complete")
PYEOF

# Navigate to Groups page so agent can immediately begin auditing
launch_firefox_to "${AC_URL}/#/groups" 8
take_screenshot /tmp/group_membership_audit_start.png
echo "=== group_membership_audit setup complete ==="
