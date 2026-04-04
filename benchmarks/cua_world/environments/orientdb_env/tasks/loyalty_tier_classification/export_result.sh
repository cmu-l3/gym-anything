#!/bin/bash
echo "=== Exporting Loyalty Tier Classification Result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/loyalty_report.txt"

# 1. Report File Check
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    # Read first 100 lines of report
    REPORT_CONTENT=$(head -n 100 "$REPORT_PATH")
fi

# 2. Database State Extraction
# We use a python script to query OrientDB and format the state as JSON
# This avoids complex bash JSON parsing
echo "Querying database state..."

cat > /tmp/extract_db_state.py << 'EOF'
import sys
import json
import urllib.request
import base64

BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

def sql(command):
    try:
        req = urllib.request.Request(
            f"{BASE_URL}/command/demodb/sql",
            data=json.dumps({"command": command}).encode(),
            headers=HEADERS,
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read()).get("result", [])
    except Exception as e:
        return []

def get_schema():
    try:
        req = urllib.request.Request(
            f"{BASE_URL}/database/demodb",
            headers=HEADERS,
            method="GET"
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except Exception:
        return {}

state = {}

# Schema Checks
schema = get_schema()
classes = {c["name"]: c for c in schema.get("classes", [])}

state["class_LoyaltyTiers_exists"] = "LoyaltyTiers" in classes
state["class_BelongsToTier_exists"] = "BelongsToTier" in classes
state["profiles_properties"] = [p["name"] for p in classes.get("Profiles", {}).get("properties", [])]

# Data Checks - Loyalty Tiers
if state["class_LoyaltyTiers_exists"]:
    tiers = sql("SELECT TierName, MinSpend, Benefits FROM LoyaltyTiers")
    state["tiers_data"] = tiers
else:
    state["tiers_data"] = []

# Data Checks - Profiles and Spending
# We fetch all profiles and their calculated spend to verify agent's logic
# Query: Get Profile info, LoyaltyTier property, and calculate sum of orders
# Note: Complex aggregations in one query can be tricky in older OrientDB versions via HTTP
# We will fetch raw data and aggregate in Python for ground truth comparison
profiles_raw = sql("SELECT Email, Name, Surname, LoyaltyTier, out('BelongsToTier').TierName as LinkedTierName FROM Profiles")
orders_raw = sql("SELECT in('HasOrder').in('HasCustomer').out('HasProfile').Email as Email, Price FROM Orders")

# Map orders to emails
spending_map = {}
for o in orders_raw:
    # The query returns a list of emails (should be 1 per order path)
    emails = o.get("Email", [])
    price = o.get("Price", 0)
    if isinstance(emails, list):
        for email in emails:
            spending_map[email] = spending_map.get(email, 0) + price
    elif isinstance(emails, str):
        spending_map[emails] = spending_map.get(emails, 0) + price

# Combine
profile_data = []
for p in profiles_raw:
    email = p.get("Email")
    actual_tier_prop = p.get("LoyaltyTier")
    linked_tiers = p.get("LinkedTierName", [])
    
    # LinkedTierName could be a list if multiple edges, or single value, or null
    linked_tier_edge = None
    if isinstance(linked_tiers, list) and len(linked_tiers) > 0:
        linked_tier_edge = linked_tiers[0]
    elif isinstance(linked_tiers, str):
        linked_tier_edge = linked_tiers
        
    profile_data.append({
        "email": email,
        "name": p.get("Name"),
        "surname": p.get("Surname"),
        "actual_tier_prop": actual_tier_prop,
        "linked_tier_edge": linked_tier_edge,
        "calculated_spend": spending_map.get(email, 0)
    })

state["profiles"] = profile_data

print(json.dumps(state))
EOF

python3 /tmp/extract_db_state.py > /tmp/db_state.json

# 3. Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Construct Final JSON
# We merge the shell variables and the python JSON output
jq -n \
    --argjson db_state "$(cat /tmp/db_state.json)" \
    --arg report_exists "$REPORT_EXISTS" \
    --arg report_content "$REPORT_CONTENT" \
    --arg report_created "$REPORT_CREATED_DURING" \
    --arg task_start "$TASK_START" \
    --arg task_end "$TASK_END" \
    '{
        db_state: $db_state,
        report: {
            exists: ($report_exists == "true"),
            content: $report_content,
            created_during_task: ($report_created == "true")
        },
        meta: {
            task_start: $task_start,
            task_end: $task_end,
            screenshot: "/tmp/task_final.png"
        }
    }' > /tmp/task_result.json

# Cleanup
rm -f /tmp/extract_db_state.py /tmp/db_state.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="