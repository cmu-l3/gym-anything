#!/bin/bash
echo "=== Setting up rd_department_onboarding task ==="

source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login > /dev/null 2>&1 || true

# -------------------------------------------------------
# Clean up artifacts from prior runs BEFORE recording timestamp
# -------------------------------------------------------
echo "Cleaning up pre-existing test data..."

# v3.5.2 API returns {items:[...]} with PascalCase field names

# Delete access rules first (they reference groups/zones)
for RNAME in "R&D Access" "IT Lab Support"; do
    R_IDS=$(ac_api GET "/accessRules" 2>/dev/null | jq -r --arg n "$RNAME" '.items[]? | select(.Name==$n) | .Id' 2>/dev/null || true)
    for id in $R_IDS; do
        [ -n "$id" ] && ac_api DELETE "/accessRules/$id" > /dev/null 2>&1 && echo "  Cleaned rule $RNAME ($id)"
    done
done

# Delete "Flex Hours" time profile
TP_IDS=$(ac_api GET "/timeProfiles" 2>/dev/null | jq -r '.items[]? | select(.Name=="Flex Hours") | .Id' 2>/dev/null || true)
for id in $TP_IDS; do [ -n "$id" ] && ac_api DELETE "/timeProfiles/$id" > /dev/null 2>&1 && echo "  Cleaned time profile Flex Hours ($id)"; done

# Delete "R&D Engineering" group
G_IDS=$(ac_api GET "/groups" 2>/dev/null | jq -r '.items[]? | select(.Name=="R&D Engineering") | .Id' 2>/dev/null || true)
for id in $G_IDS; do [ -n "$id" ] && ac_api DELETE "/groups/$id" > /dev/null 2>&1 && echo "  Cleaned group R&D Engineering ($id)"; done

# Delete "R&D Lab" zone
Z_IDS=$(ac_api GET "/zones" 2>/dev/null | jq -r '.items[]? | select(.Name=="R&D Lab") | .Id' 2>/dev/null || true)
for id in $Z_IDS; do [ -n "$id" ] && ac_api DELETE "/zones/$id" > /dev/null 2>&1 && echo "  Cleaned zone R&D Lab ($id)"; done

# Delete new users from prior runs
ac_delete_user_by_name "Amelia" "Chen"
ac_delete_user_by_name "Marcus" "Rivera"

# Use Python for complex cleanup (card removal, Darnell reset, PIN removal)
# This uses the session cookie already set by ac_login above
python3 << 'PYEOF'
import requests, urllib3, json
urllib3.disable_warnings()
s = requests.Session()
s.verify = False
AC = "https://localhost:9443"
s.put(f"{AC}/api/v3/login", json={"login":"admin","password":"Admin2n1!"}, timeout=10)

users_resp = s.get(f"{AC}/api/v3/users", timeout=10)
try:
    all_users = users_resp.json().get("items", [])
except:
    all_users = []

replacement_cards = {f"000670000{i}" for i in range(1, 10)} | {"0006700010"}

for u in all_users:
    uid = u.get("Id")
    name = u.get("Name", "")
    if not uid:
        continue
    cards = u.get("AccessCredentials", {}).get("Cards", [])

    # Remove stale replacement-range cards
    for i, card in enumerate(cards):
        if card in replacement_cards:
            # Remove card by index using JSON Patch
            r = s.patch(f"{AC}/api/v3/users/{uid}",
                       json=[{"op":"remove","path":f"/AccessCredentials/Cards/{i}"}],
                       headers={"Content-Type":"application/json-patch+json"}, timeout=10)
            print(f"  Removed stale card {card} from {name}: {r.status_code}")

    # Reset Darnell Robinson
    if name == "Darnell Robinson":
        email = u.get("Account", {}).get("Email", "")
        if email != "d.robinson@buildingtech.com":
            s.patch(f"{AC}/api/v3/users/{uid}",
                   json=[{"op":"replace","path":"/Account/Email","value":"d.robinson@buildingtech.com"}],
                   headers={"Content-Type":"application/json-patch+json"}, timeout=10)
            print("  Reset Darnell email to original")
        # Remove PIN if present
        pin = u.get("AccessCredentials", {}).get("Pin")
        if pin:
            s.patch(f"{AC}/api/v3/users/{uid}",
                   json=[{"op":"replace","path":"/AccessCredentials/Pin","value":None}],
                   headers={"Content-Type":"application/json-patch+json"}, timeout=10)
            print("  Removed PIN from Darnell Robinson")
        print("  Reset Darnell Robinson to clean state")

    # Remove PINs from Kwame Asante and Mei-Ling Zhang
    if name in ("Kwame Asante", "Mei-Ling Zhang"):
        pin = u.get("AccessCredentials", {}).get("Pin")
        if pin:
            s.patch(f"{AC}/api/v3/users/{uid}",
                   json=[{"op":"replace","path":"/AccessCredentials/Pin","value":None}],
                   headers={"Content-Type":"application/json-patch+json"}, timeout=10)
            print(f"  Removed PIN from {name}")

print("Cleanup complete")
PYEOF

# Delete report file
rm -f /home/ga/Documents/rd_onboarding.txt
mkdir -p /home/ga/Documents

# -------------------------------------------------------
# Record task start time AFTER cleanup
# -------------------------------------------------------
date +%s > /tmp/task_start_time.txt

# Ensure profile directory exists (may not be created yet by background setup)
mkdir -p "$PROFILE_DIR"
chown -R ga:ga "$(dirname "$PROFILE_DIR")" 2>/dev/null || true

# Launch Firefox to the AC dashboard
launch_firefox_to "${AC_URL}/" 12

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
