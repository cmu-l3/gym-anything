#!/bin/bash
echo "=== Setting up security_staff_2fa_audit task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# -------------------------------------------------------
# Prepare the starting state:
#
# Policy 1 setup:
#   Remove any PINs from Security Staff members
#   (Victor Schulz, Tamara Kowalski, Leon Fischer)
#   so they start with only RFID cards.
#
# Policy 2 setup:
#   Disable Priya Nair and Carlos Mendoza.
#   Verify each still has their RFID card.
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

# ── Policy 1: Remove PINs from Security Staff ─────────────────────────────
security_staff = [
    ("Victor",  "Schulz"),
    ("Tamara",  "Kowalski"),
    ("Leon",    "Fischer"),
]
for first, last in security_staff:
    u = find_user(first, last)
    if not u:
        print(f"  WARNING: Security Staff member {first} {last} not found")
        continue
    uid = u["id"]
    # Ensure user is enabled
    ac("PATCH", f"/users/{uid}", {"enabled": True})
    # Remove all PIN credentials (keep cards)
    creds = ac("GET", f"/users/{uid}/credentials")
    if not isinstance(creds, list):
        creds = []
    for c in creds:
        if c.get("type") == "pin":
            cid = c.get("id")
            if cid:
                ac("DELETE", f"/users/{uid}/credentials/{cid}")
                print(f"  Removed PIN from {first} {last}")
    # If they have no card either, add their seeded card back
    creds_after = ac("GET", f"/users/{uid}/credentials")
    if not isinstance(creds_after, list): creds_after = []
    has_card = any(c.get("type") == "card" for c in creds_after)
    if not has_card:
        # Re-assign seeded card numbers
        card_map = {
            ("Victor",  "Schulz"):   "0004521887",
            ("Tamara",  "Kowalski"): "0004521888",
            ("Leon",    "Fischer"):  "0007654321",
        }
        card = card_map.get((first, last))
        if card:
            ac("POST", f"/users/{uid}/credentials", {"type": "card", "cardNumber": card})
            print(f"  Restored card {card} to {first} {last}")
    print(f"  {first} {last}: PIN removed, card retained, account enabled")

# ── Policy 2: Disable Priya Nair and Carlos Mendoza ──────────────────────
to_disable = [
    ("Priya",   "Nair",    "0004521875"),
    ("Carlos",  "Mendoza", "0004521880"),
]
for first, last, expected_card in to_disable:
    u = find_user(first, last)
    if not u:
        print(f"  WARNING: {first} {last} not found — seeding incomplete")
        continue
    uid = u["id"]
    # Disable the account
    ac("PATCH", f"/users/{uid}", {"enabled": False})
    # Ensure they have their card (so there's something to revoke)
    creds = ac("GET", f"/users/{uid}/credentials")
    if not isinstance(creds, list): creds = []
    has_expected_card = any(c.get("cardNumber") == expected_card for c in creds)
    if not has_expected_card:
        # Remove all current credentials and re-add the expected card
        for c in creds:
            cid = c.get("id")
            if cid:
                ac("DELETE", f"/users/{uid}/credentials/{cid}")
        ac("POST", f"/users/{uid}/credentials",
           {"type": "card", "cardNumber": expected_card})
        print(f"  Restored card {expected_card} to {first} {last}")
    print(f"  {first} {last}: disabled with card {expected_card}")

print("security_staff_2fa_audit setup complete")
PYEOF

# Start at Users page for easy discovery
launch_firefox_to "${AC_URL}/#/users" 8
take_screenshot /tmp/security_staff_2fa_audit_start.png
echo "=== security_staff_2fa_audit setup complete ==="
