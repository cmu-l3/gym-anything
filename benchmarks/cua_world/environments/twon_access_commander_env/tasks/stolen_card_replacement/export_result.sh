#!/bin/bash
echo "=== Exporting stolen_card_replacement result ==="
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

COMPROMISED_CARDS = {
    "0004521820", "0004521821", "0004521822", "0004521823", "0004521824",
    "0004521825", "0004521826", "0004521827", "0004521828", "0004521829",
}
REPLACEMENT_RANGE_START = 4522100
REPLACEMENT_RANGE_END   = 4522109

all_users = ac("GET", "/users")
if not isinstance(all_users, list):
    all_users = []

target_names = {
    ("Heather", "Morrison"),
    ("Robert", "Nakamura"),
}

user_results = {}

for u in all_users:
    uid = u.get("id")
    first = u.get("firstName", "")
    last  = u.get("lastName", "")

    if (first, last) not in target_names:
        continue

    creds = ac("GET", f"/users/{uid}/credentials")
    if not isinstance(creds, list):
        creds = []

    card_numbers = [c.get("cardNumber", "") for c in creds if c.get("type") == "card"]
    has_compromised = any(cn in COMPROMISED_CARDS for cn in card_numbers)
    replacement_cards = [
        cn for cn in card_numbers
        if cn.isdigit() and REPLACEMENT_RANGE_START <= int(cn) <= REPLACEMENT_RANGE_END
    ]

    user_results[f"{first} {last}"] = {
        "id": uid,
        "enabled": u.get("enabled", True),
        "card_numbers": card_numbers,
        "has_compromised_card": has_compromised,
        "has_replacement_card": len(replacement_cards) > 0,
        "replacement_cards": replacement_cards,
        "all_credentials": [
            {"type": c.get("type"), "cardNumber": c.get("cardNumber")} for c in creds
        ],
    }

result = {"user_results": user_results}

with open("/tmp/stolen_card_replacement_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("stolen_card_replacement export complete")
for name, info in user_results.items():
    print(f"  {name}: cards={info['card_numbers']}, "
          f"has_compromised={info['has_compromised_card']}, "
          f"has_replacement={info['has_replacement_card']}, "
          f"enabled={info['enabled']}")
PYEOF

echo "=== stolen_card_replacement export complete ==="
