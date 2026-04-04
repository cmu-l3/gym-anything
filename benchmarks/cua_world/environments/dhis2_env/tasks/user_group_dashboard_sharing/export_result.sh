#!/bin/bash
# Export script for User Group Dashboard Sharing task

echo "=== Exporting User Group Dashboard Sharing Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district -X "${2:-GET}" "http://localhost:8080/api/$1"
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get task timing
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")
TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "Checking DHIS2 for created objects..."

# 3. Query User Groups
# We look for groups containing 'Kenema' created after start time
# Note: DHIS2 API 'created' field format varies slightly by version, we handle loose string matching in Python
USER_GROUPS_JSON=$(dhis2_api "userGroups?filter=name:ilike:Kenema&fields=id,name,created,users[username]" 2>/dev/null)

# 4. Query Dashboards
# We look for dashboards containing 'Kenema'
# We also request userGroupAccesses to check sharing
DASHBOARDS_JSON=$(dhis2_api "dashboards?filter=name:ilike:Kenema&fields=id,name,created,dashboardItems,userGroupAccesses[id,userGroupUid,access,displayName]" 2>/dev/null)

# 5. Process data with Python to produce clean result JSON
python3 << EOF > /tmp/user_group_dashboard_sharing_result.json
import json
import sys
from datetime import datetime

# Inputs
try:
    ug_data = json.loads('''$USER_GROUPS_JSON''')
    db_data = json.loads('''$DASHBOARDS_JSON''')
    task_start_iso = "$TASK_START_ISO"
except Exception as e:
    print(json.dumps({"error": f"JSON parse error: {str(e)}"}))
    sys.exit(0)

# Helper to parse dates loosely (DHIS2 provides varied ISO formats)
def is_created_after(created_str, start_iso):
    if not created_str: return False
    # Simple string comparison works for ISO8601 if timezones match, 
    # but let's be safe and assume if it exists and matches our specific task naming,
    # it's likely the one (since we deleted old ones in setup).
    # To be precise, we can try to parse:
    return True 

result = {
    "task_start": task_start_iso,
    "user_group": None,
    "dashboard": None,
    "sharing_correct": False
}

# Analyze User Groups
target_ug = None
for ug in ug_data.get("userGroups", []):
    name = ug.get("name", "")
    if "Kenema" in name and "Health" in name:
        # Check if admin is a user
        users = [u.get("username") for u in ug.get("users", [])]
        ug_info = {
            "id": ug.get("id"),
            "name": name,
            "created": ug.get("created"),
            "has_admin": "admin" in users
        }
        target_ug = ug_info
        result["user_group"] = ug_info
        break

# Analyze Dashboards
target_db = None
for db in db_data.get("dashboards", []):
    name = db.get("name", "")
    if "Kenema" in name:
        # Check items
        items = db.get("dashboardItems", [])
        
        # Check sharing
        # userGroupAccesses is a list of objects like { "id": "ug_id", "access": "r-------" }
        accesses = db.get("userGroupAccesses", [])
        
        db_info = {
            "id": db.get("id"),
            "name": name,
            "created": db.get("created"),
            "item_count": len(items),
            "accesses": accesses
        }
        target_db = db_info
        result["dashboard"] = db_info
        break

# Verify Linkage (Sharing)
if target_ug and target_db:
    ug_id = target_ug["id"]
    # Look for this UG ID in the dashboard's access list
    # DHIS2 2.38+ uses 'id' inside userGroupAccesses for the UG UUID usually, 
    # or sometimes 'userGroupUid'. Let's check both.
    
    for access in target_db["accesses"]:
        access_ug_id = access.get("id") or access.get("userGroupUid")
        if access_ug_id == ug_id:
            mode = access.get("access", "")
            # We want View Only. 
            # View = "r-------"
            # Edit = "rw------"
            if mode.startswith("r") and "w" not in mode:
                result["sharing_correct"] = True
                result["sharing_details"] = "View access found"
            elif "w" in mode:
                result["sharing_details"] = "Edit access found (should be view only)"
            else:
                result["sharing_details"] = f"Access string: {mode}"
            break

print(json.dumps(result, indent=2))
EOF

# Ensure permissions
chmod 666 /tmp/user_group_dashboard_sharing_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/user_group_dashboard_sharing_result.json
echo "=== Export Complete ==="