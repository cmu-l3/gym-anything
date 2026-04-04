#!/bin/bash
echo "=== Exporting GDPR Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# We need to perform verification checks INSIDE the container because we need DB access
# Create a python script to run verification checks against the local OrientDB
cat > /tmp/verify_local.py << 'PYEOF'
import requests
import json
import sys

BASE_URL = "http://localhost:2480"
ROOT_AUTH = ("root", "GymAnything123!")
PARTNER_AUTH = ("us_partner", "password123")
DB = "demodb"

results = {
    "user_exists": False,
    "role_exists": False,
    "policy_exists": False,
    "policy_predicate": None,
    "policy_applied": False,
    "partner_login_success": False,
    "partner_row_count": -1,
    "partner_rows_sample": [],
    "root_row_count": -1,
    "all_partner_rows_are_american": False,
    "partner_sees_subset": False
}

def sql_command(query, auth):
    try:
        resp = requests.post(
            f"{BASE_URL}/command/{DB}/sql",
            json={"command": query},
            auth=auth,
            headers={"Content-Type": "application/json"},
            timeout=5
        )
        if resp.status_code == 200:
            return resp.json().get("result", [])
        return []
    except:
        return []

def sql_query(query, auth):
    # Use command endpoint for SELECT as well for consistency in this script context
    return sql_command(query, auth)

# 1. Check User and Role (as Root)
users = sql_query("SELECT name, roles.name as roles FROM OUser", ROOT_AUTH)
for u in users:
    if u.get("name") == "us_partner":
        results["user_exists"] = True
        if "us_analytics" in u.get("roles", []):
            results["role_exists"] = True

# 2. Check Policy Existence (as Root)
policies = sql_query("SELECT name, read FROM OSecurityPolicy WHERE name = 'us_only_policy'", ROOT_AUTH)
if policies:
    results["policy_exists"] = True
    results["policy_predicate"] = policies[0].get("read", "")

# 3. Check if Policy is applied to Profiles class for us_analytics role (as Root)
# This is stored in ORole.policies map usually, or OSecurityPolicy.
# Querying ORole is reliable.
roles = sql_query("SELECT name, policies FROM ORole WHERE name = 'us_analytics'", ROOT_AUTH)
if roles:
    role_policies = roles[0].get("policies", {})
    # Format might be {"database.class.Profiles": "rid_of_policy"}
    # We check if keys contain our target
    for k, v in role_policies.items():
        if "database.class.Profiles" in k:
            results["policy_applied"] = True

# 4. DATA VISIBILITY CHECK (The most important part)
# Try to query as the Partner
try:
    resp = requests.post(
        f"{BASE_URL}/command/{DB}/sql",
        json={"command": "SELECT Name, Nationality FROM Profiles"},
        auth=PARTNER_AUTH,
        headers={"Content-Type": "application/json"},
        timeout=5
    )
    
    if resp.status_code == 200:
        results["partner_login_success"] = True
        rows = resp.json().get("result", [])
        results["partner_row_count"] = len(rows)
        results["partner_rows_sample"] = rows[:5]
        
        # Verify nationalities
        non_americans = [r for r in rows if r.get("Nationality") != "American"]
        if len(rows) > 0 and len(non_americans) == 0:
            results["all_partner_rows_are_american"] = True
    else:
        results["partner_login_error"] = resp.status_code

except Exception as e:
    results["partner_login_exception"] = str(e)

# 5. Get Ground Truth Count (as Root)
root_rows = sql_query("SELECT count(*) as cnt FROM Profiles", ROOT_AUTH)
if root_rows:
    results["root_row_count"] = root_rows[0].get("cnt", 0)

if results["partner_row_count"] >= 0 and results["root_row_count"] > 0:
    if results["partner_row_count"] < results["root_row_count"]:
        results["partner_sees_subset"] = True

print(json.dumps(results, indent=2))
PYEOF

# Run the python script
python3 /tmp/verify_local.py > /tmp/verification_data.json 2>/dev/null

# Prepare final JSON
# We combine the python output with file timestamps and screenshot info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "verification_data": $(cat /tmp/verification_data.json)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json