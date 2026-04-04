#!/bin/bash
echo "=== Exporting new_department_provisioning result ==="
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

# ── 1. Check Executive Operations group ────────────────────────────────────
all_groups = ac("GET", "/groups")
if not isinstance(all_groups, list): all_groups = []

exec_group = next((g for g in all_groups if g.get("name") == "Executive Operations"), None)

exec_group_info = {"exists": False, "id": None, "members": []}
if exec_group:
    gid = exec_group["id"]
    exec_group_info["exists"] = True
    exec_group_info["id"] = gid
    members_resp = ac("GET", f"/groups/{gid}/members")
    if isinstance(members_resp, list):
        member_ids = [m.get("id") or m.get("userId") for m in members_resp if isinstance(m, dict)]
    elif isinstance(members_resp, dict):
        raw = members_resp.get("members", members_resp.get("items", []))
        member_ids = [m.get("id") or m.get("userId") for m in raw if isinstance(m, dict)]
    else:
        member_ids = []
    member_ids = [mid for mid in member_ids if mid is not None]
    # Resolve to user details
    all_users = ac("GET", "/users")
    if not isinstance(all_users, list): all_users = []
    user_map = {u["id"]: u for u in all_users if "id" in u}
    members = []
    for mid in member_ids:
        u = user_map.get(mid, {})
        members.append({
            "id": mid,
            "firstName": u.get("firstName", ""),
            "lastName": u.get("lastName", ""),
            "email": u.get("email", ""),
        })
    exec_group_info["members"] = members
    exec_group_info["member_ids"] = member_ids
else:
    all_users = ac("GET", "/users")
    if not isinstance(all_users, list): all_users = []

# ── 2. Check Executive Hours time profile ─────────────────────────────────
exec_profile_info = {"exists": False, "name": None, "schedules": []}
for endpoint in ["/timeProfiles", "/time-profiles"]:
    profiles = ac("GET", endpoint)
    if isinstance(profiles, list):
        tp = next((p for p in profiles if p.get("name") == "Executive Hours"), None)
        if tp:
            exec_profile_info["exists"] = True
            exec_profile_info["name"] = tp.get("name")
            exec_profile_info["schedules"] = tp.get("schedules", [])
        break

# ── 3. Check Elena Vasquez user ───────────────────────────────────────────
elena_info = {"exists": False, "id": None, "in_exec_group": False, "has_card_0004522050": False}
elena = next((u for u in all_users
              if u.get("firstName") == "Elena" and u.get("lastName") == "Vasquez"), None)
if elena:
    uid = elena["id"]
    elena_info["exists"] = True
    elena_info["id"] = uid
    elena_info["email"] = elena.get("email", "")
    elena_info["phone"] = elena.get("phone", "")
    elena_info["company"] = elena.get("company", "")
    # Check group membership
    if exec_group_info["exists"]:
        elena_info["in_exec_group"] = uid in exec_group_info.get("member_ids", [])
    # Check credentials
    creds = ac("GET", f"/users/{uid}/credentials")
    if not isinstance(creds, list): creds = []
    card_numbers = [c.get("cardNumber", "") for c in creds if c.get("type") == "card"]
    elena_info["has_card_0004522050"] = "0004522050" in card_numbers
    elena_info["credentials"] = [{"type": c.get("type"), "cardNumber": c.get("cardNumber")} for c in creds]

# ── 4. Check IT Department members in Executive Operations ────────────────
it_group = next((g for g in all_groups if g.get("name") == "IT Department"), None)
it_member_ids_in_exec = []
known_it_emails = ["k.asante@buildingtech.com", "m.zhang@buildingtech.com"]
it_in_exec = {}
if it_group:
    it_members_resp = ac("GET", f"/groups/{it_group['id']}/members")
    if isinstance(it_members_resp, list):
        it_member_ids = [m.get("id") or m.get("userId") for m in it_members_resp if isinstance(m, dict)]
    elif isinstance(it_members_resp, dict):
        raw = it_members_resp.get("members", it_members_resp.get("items", []))
        it_member_ids = [m.get("id") or m.get("userId") for m in raw if isinstance(m, dict)]
    else:
        it_member_ids = []
    it_member_ids = [mid for mid in it_member_ids if mid is not None]
    exec_member_ids = set(exec_group_info.get("member_ids", []))
    for mid in it_member_ids:
        u = user_map.get(mid, {}) if exec_group_info["exists"] else {}
        email = u.get("email", "")
        it_in_exec[email] = mid in exec_member_ids

result = {
    "exec_group": exec_group_info,
    "exec_profile": exec_profile_info,
    "elena": elena_info,
    "it_members_in_exec": it_in_exec,
}

with open("/tmp/new_department_provisioning_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("new_department_provisioning export complete")
print(f"  Executive Operations group exists: {exec_group_info['exists']}")
print(f"  Executive Hours profile exists: {exec_profile_info['exists']}")
print(f"  Elena Vasquez exists: {elena_info['exists']}")
print(f"  IT members in exec group: {it_in_exec}")
PYEOF

echo "=== new_department_provisioning export complete ==="
