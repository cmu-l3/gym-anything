#!/bin/bash
echo "=== Exporting security_staff_2fa_audit result ==="
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

user_map = {u["id"]: u for u in all_users if "id" in u}

# ── Get Security Staff group members ──────────────────────────────────────
sec_group = next((g for g in all_groups if g.get("name") == "Security Staff"), None)
sec_member_info = []
if sec_group:
    members_resp = ac("GET", f"/groups/{sec_group['id']}/members")
    if isinstance(members_resp, list):
        member_ids = [m.get("id") or m.get("userId") for m in members_resp if isinstance(m, dict)]
    elif isinstance(members_resp, dict):
        raw = members_resp.get("members", members_resp.get("items", []))
        member_ids = [m.get("id") or m.get("userId") for m in raw if isinstance(m, dict)]
    else:
        member_ids = []
    member_ids = [mid for mid in member_ids if mid is not None]

    for mid in member_ids:
        u = user_map.get(mid, {})
        uid = mid
        creds = ac("GET", f"/users/{uid}/credentials")
        if not isinstance(creds, list): creds = []
        has_card = any(c.get("type") == "card" for c in creds)
        has_pin  = any(c.get("type") == "pin"  for c in creds)
        pins     = [c.get("pin", "") for c in creds if c.get("type") == "pin"]
        sec_member_info.append({
            "id": uid,
            "firstName": u.get("firstName", ""),
            "lastName":  u.get("lastName",  ""),
            "email":     u.get("email",     ""),
            "has_card":  has_card,
            "has_pin":   has_pin,
            "pins":      pins,
            "credential_count": len(creds),
        })

# ── Check disabled users ───────────────────────────────────────────────────
disabled_targets = {
    ("Priya",   "Nair"),
    ("Carlos",  "Mendoza"),
}
disabled_user_info = {}

for u in all_users:
    first = u.get("firstName", "")
    last  = u.get("lastName",  "")
    if (first, last) not in disabled_targets:
        continue
    uid = u["id"]
    creds = ac("GET", f"/users/{uid}/credentials")
    if not isinstance(creds, list): creds = []
    disabled_user_info[f"{first} {last}"] = {
        "id":          uid,
        "enabled":     u.get("enabled", True),
        "credential_count": len(creds),
        "credentials": [{"type": c.get("type"), "cardNumber": c.get("cardNumber")} for c in creds],
    }

result = {
    "security_staff_members": sec_member_info,
    "disabled_users": disabled_user_info,
}

with open("/tmp/security_staff_2fa_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("security_staff_2fa_audit export complete")
for m in sec_member_info:
    print(f"  Security Staff: {m['firstName']} {m['lastName']} — "
          f"card={m['has_card']}, pin={m['has_pin']}")
for name, info in disabled_user_info.items():
    print(f"  Disabled user: {name} — "
          f"enabled={info['enabled']}, cred_count={info['credential_count']}")
PYEOF

echo "=== security_staff_2fa_audit export complete ==="
