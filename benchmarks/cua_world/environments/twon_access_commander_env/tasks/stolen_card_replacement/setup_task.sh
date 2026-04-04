#!/bin/bash
echo "=== Setting up stolen_card_replacement task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# -------------------------------------------------------
# Inject compromised cards:
#   Heather Morrison: replace existing card with 0004521820
#   Robert Nakamura:  replace existing card with 0004521821
#
# Also remove any pre-existing replacement cards
# (0004522100-0004522109) from all users in case a prior
# run assigned them.
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

def find_user(first, last):
    return next((u for u in all_users
                 if u.get("firstName") == first and u.get("lastName") == last), None)

COMPROMISED_RANGE = set(
    f"000452182{i}" for i in range(10)
) | {f"0004521820", "0004521821", "0004521822", "0004521823", "0004521824",
     "0004521825", "0004521826", "0004521827", "0004521828", "0004521829"}

REPLACEMENT_RANGE = {f"000452210{i}" for i in range(10)}

# Step 1: Remove any replacement range cards from all users (clean prior runs)
for u in all_users:
    uid = u.get("id")
    creds = ac("GET", f"/users/{uid}/credentials")
    if not isinstance(creds, list):
        continue
    for c in creds:
        card_num = c.get("cardNumber", "")
        if card_num in REPLACEMENT_RANGE:
            cid = c.get("id")
            if cid:
                ac("DELETE", f"/users/{uid}/credentials/{cid}")
                print(f"  Removed prior replacement card {card_num} from {u.get('firstName')} {u.get('lastName')}")

# Step 2: Assign compromised cards to Heather and Robert
targets = [
    ("Heather", "Morrison", "0004521820"),
    ("Robert",  "Nakamura",  "0004521821"),
]

for first, last, compromised_card in targets:
    u = find_user(first, last)
    if not u:
        print(f"  WARNING: {first} {last} not found — seeding incomplete")
        continue
    uid = u["id"]
    # Ensure user is enabled
    ac("PATCH", f"/users/{uid}", {"enabled": True})
    # Remove ALL existing credentials (both legit and any prior compromised)
    creds = ac("GET", f"/users/{uid}/credentials")
    if isinstance(creds, list):
        for c in creds:
            cid = c.get("id")
            if cid:
                ac("DELETE", f"/users/{uid}/credentials/{cid}")
                print(f"  Cleared credential {c.get('cardNumber', c.get('type', '?'))} from {first} {last}")
    # Assign the compromised card
    resp = ac("POST", f"/users/{uid}/credentials",
              {"type": "card", "cardNumber": compromised_card})
    print(f"  Assigned compromised card {compromised_card} to {first} {last}: {json.dumps(resp)[:60]}")

print("stolen_card_replacement setup complete")
PYEOF

# Navigate to Users list so agent can browse
launch_firefox_to "${AC_URL}/#/users" 8
take_screenshot /tmp/stolen_card_replacement_start.png
echo "=== stolen_card_replacement setup complete ==="
