#!/bin/bash
echo "=== Setting up contractor_offboarding task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# -------------------------------------------------------
# Ensure the three Meridian Facilities contractors exist
# with their RFID cards, and are currently ENABLED.
# The seed script normally creates them; this setup verifies
# they are present and resets them to the expected starting state.
# -------------------------------------------------------

MERIDIAN_USERS='[
  {"firstName":"Nadia",   "lastName":"Ivanova",  "email":"n.ivanova@meridianfacilities.com",  "phone":"+1-847-555-0118","company":"Meridian Facilities","cardNumber":"0004521890"},
  {"firstName":"Tomas",   "lastName":"Guerrero", "email":"t.guerrero@meridianfacilities.com", "phone":"+1-847-555-0125","company":"Meridian Facilities","cardNumber":"0004521891"},
  {"firstName":"Olumide", "lastName":"Adeyemi",  "email":"o.adeyemi@meridianfacilities.com",  "phone":"+1-847-555-0132","company":"Meridian Facilities","cardNumber":"0004521892"}
]'

# Get all current users
ALL_USERS=$(ac_api GET "/users" 2>/dev/null)

echo "Checking/restoring Meridian Facilities users..."
python3 << PYEOF
import json, subprocess, os

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

meridian_specs = [
    {"firstName":"Nadia",   "lastName":"Ivanova",  "email":"n.ivanova@meridianfacilities.com",  "phone":"+1-847-555-0118","company":"Meridian Facilities","card":"0004521890"},
    {"firstName":"Tomas",   "lastName":"Guerrero", "email":"t.guerrero@meridianfacilities.com", "phone":"+1-847-555-0125","company":"Meridian Facilities","card":"0004521891"},
    {"firstName":"Olumide", "lastName":"Adeyemi",  "email":"o.adeyemi@meridianfacilities.com",  "phone":"+1-847-555-0132","company":"Meridian Facilities","card":"0004521892"},
]

for spec in meridian_specs:
    # Find existing user
    existing = [u for u in all_users if u.get("firstName") == spec["firstName"]
                                     and u.get("lastName") == spec["lastName"]]
    if existing:
        uid = existing[0]["id"]
        # Re-enable user (reset to starting state: enabled=True)
        ac("PATCH", f"/users/{uid}", {"enabled": True})
        print(f"  Re-enabled existing user: {spec['firstName']} {spec['lastName']} (id={uid})")
        # Remove all existing credentials so we can re-add the expected card
        creds = ac("GET", f"/users/{uid}/credentials")
        if isinstance(creds, list):
            for c in creds:
                cid = c.get("id")
                if cid:
                    ac("DELETE", f"/users/{uid}/credentials/{cid}")
                    print(f"    Removed old credential {cid}")
    else:
        # Create user
        user_data = {
            "firstName": spec["firstName"], "lastName": spec["lastName"],
            "email": spec["email"], "phone": spec["phone"],
            "company": spec["company"], "enabled": True
        }
        resp = ac("POST", "/users", user_data)
        uid = resp.get("id") or resp.get("userId")
        print(f"  Created user: {spec['firstName']} {spec['lastName']} (id={uid})")

    # Assign RFID card
    if uid:
        ac("POST", f"/users/{uid}/credentials", {"type": "card", "cardNumber": spec["card"]})
        print(f"  Assigned card {spec['card']} to {spec['firstName']} {spec['lastName']}")

# Also ensure Contractors group has these members
groups = ac("GET", "/groups")
if not isinstance(groups, list):
    groups = []

contractors_group = next((g for g in groups if g.get("name") == "Contractors"), None)
if contractors_group:
    gid = contractors_group["id"]
    # Get fresh user list
    all_users2 = ac("GET", "/users")
    if not isinstance(all_users2, list):
        all_users2 = []
    for spec in meridian_specs:
        u = next((x for x in all_users2 if x.get("firstName") == spec["firstName"]
                  and x.get("lastName") == spec["lastName"]), None)
        if u:
            ac("POST", f"/groups/{gid}/members", {"userId": u["id"]})

print("Meridian Facilities setup complete")
PYEOF

# Record baseline: all 3 contractors should currently be enabled with credentials
date +%s > /tmp/contractor_offboarding_start_ts

# Navigate Firefox to Users page (show user list so agent can browse/search)
launch_firefox_to "${AC_URL}/#/users" 8
take_screenshot /tmp/contractor_offboarding_start.png
echo "=== contractor_offboarding setup complete ==="
