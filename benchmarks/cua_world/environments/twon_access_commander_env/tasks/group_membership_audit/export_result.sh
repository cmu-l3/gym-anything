#!/bin/bash
echo "=== Exporting group_membership_audit result ==="
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

all_users  = ac("GET", "/users")
all_groups = ac("GET", "/groups")
if not isinstance(all_users, list):  all_users  = []
if not isinstance(all_groups, list): all_groups = []

# Build user lookup by ID
user_map = {u["id"]: u for u in all_users if "id" in u}

# For each group, get its current members
group_memberships = {}
for g in all_groups:
    gid  = g.get("id")
    name = g.get("name", "")
    members_resp = ac("GET", f"/groups/{gid}/members")
    if isinstance(members_resp, list):
        member_ids = [m.get("id") or m.get("userId") for m in members_resp if isinstance(m, dict)]
    elif isinstance(members_resp, dict):
        # Some API versions return {"members": [...]}
        raw = members_resp.get("members", members_resp.get("items", []))
        member_ids = [m.get("id") or m.get("userId") for m in raw if isinstance(m, dict)]
    else:
        member_ids = []
    member_ids = [mid for mid in member_ids if mid is not None]
    group_memberships[name] = {
        "id": gid,
        "member_ids": member_ids,
    }

# Collect membership data for the two restricted groups
restricted = ["IT Department", "Security Staff"]
result_groups = {}
for grp_name in restricted:
    info = group_memberships.get(grp_name, {"id": None, "member_ids": []})
    members = []
    for mid in info["member_ids"]:
        u = user_map.get(mid, {})
        members.append({
            "id": mid,
            "firstName": u.get("firstName", ""),
            "lastName": u.get("lastName", ""),
            "company": u.get("company", ""),
            "email": u.get("email", ""),
        })
    result_groups[grp_name] = {
        "group_id": info["id"],
        "members": members,
    }

# Also record which groups the 3 Meridian contractors belong to (for collateral check)
meridian_emails = [
    "n.ivanova@meridianfacilities.com",
    "t.guerrero@meridianfacilities.com",
    "o.adeyemi@meridianfacilities.com",
]
meridian_memberships = {}
for email in meridian_emails:
    u = next((x for x in all_users if x.get("email", "").lower() == email), None)
    if not u:
        meridian_memberships[email] = {"found": False, "groups": []}
        continue
    uid = u["id"]
    user_groups = []
    for grp_name, info in group_memberships.items():
        if uid in info["member_ids"]:
            user_groups.append(grp_name)
    meridian_memberships[email] = {
        "found": True,
        "id": uid,
        "firstName": u.get("firstName"),
        "lastName": u.get("lastName"),
        "enabled": u.get("enabled", True),
        "groups": user_groups,
    }

# Record legitimate IT Department members for collateral check
# (BuildingTech Solutions employees: Kwame Asante, Mei-Ling Zhang)
legitimate_it = []
for m in result_groups.get("IT Department", {}).get("members", []):
    if m.get("company") == "BuildingTech Solutions":
        legitimate_it.append(m)

legitimate_sec = []
for m in result_groups.get("Security Staff", {}).get("members", []):
    if m.get("company") == "BuildingTech Solutions":
        legitimate_sec.append(m)

result = {
    "restricted_groups": result_groups,
    "meridian_memberships": meridian_memberships,
    "legitimate_it_count": len(legitimate_it),
    "legitimate_sec_count": len(legitimate_sec),
}

with open("/tmp/group_membership_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("group_membership_audit export complete")
for grp_name, info in result_groups.items():
    mnames = [f"{m['firstName']} {m['lastName']} ({m['company']})"
              for m in info["members"]]
    print(f"  {grp_name}: {mnames}")
PYEOF

echo "=== group_membership_audit export complete ==="
