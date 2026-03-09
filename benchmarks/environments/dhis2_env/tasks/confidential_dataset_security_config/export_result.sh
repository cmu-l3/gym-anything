#!/bin/bash
# Export script for Confidential Dataset Security Config task

echo "=== Exporting Security Config Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

echo "Querying DHIS2 API for created objects..."

# 1. Check User Group
echo "Checking User Group..."
UG_JSON=$(dhis2_api "userGroups?filter=name:eq:Mental%20Health%20Specialists&fields=id,name,created&paging=false" 2>/dev/null)

# 2. Check Data Set
echo "Checking Data Set..."
DS_JSON=$(dhis2_api "dataSets?filter=name:eq:Adolescent%20Mental%20Health%20Surveillance&fields=id,name,periodType,created,publicAccess,userGroupAccesses&paging=false" 2>/dev/null)

# Parse results using Python
echo "Parsing results..."
PYTHON_SCRIPT=$(cat <<EOF
import json, sys
from datetime import datetime

try:
    task_start_iso = "$TASK_START_ISO".replace("Z", "+00:00")
    # Clean up timezone format if needed (e.g., +0000 -> +00:00)
    if len(task_start_iso) > 5 and task_start_iso[-5] in ['+', '-'] and ':' not in task_start_iso[-5:]:
        task_start_iso = task_start_iso[:-2] + ':' + task_start_iso[-2:]
        
    try:
        task_start = datetime.fromisoformat(task_start_iso)
    except:
        task_start = datetime(2020, 1, 1)

    ug_data = json.loads('''$UG_JSON''')
    ds_data = json.loads('''$DS_JSON''')
    
    result = {
        "user_group_found": False,
        "user_group_id": "",
        "user_group_created_after_start": False,
        "data_set_found": False,
        "data_set_period": "",
        "data_set_public_access": "",
        "data_set_created_after_start": False,
        "group_access_configured": False,
        "group_access_pattern": "",
        "target_group_id_in_acl": False
    }

    # Analyze User Group
    groups = ug_data.get("userGroups", [])
    target_ug_id = ""
    if groups:
        ug = groups[0]
        result["user_group_found"] = True
        result["user_group_id"] = ug.get("id")
        target_ug_id = ug.get("id")
        
        # Check creation time
        created_str = ug.get("created", "")
        if created_str:
            created_str = created_str.replace("Z", "+00:00")
            try:
                created = datetime.fromisoformat(created_str)
                if created >= task_start:
                    result["user_group_created_after_start"] = True
            except:
                pass

    # Analyze Data Set
    datasets = ds_data.get("dataSets", [])
    if datasets:
        ds = datasets[0]
        result["data_set_found"] = True
        result["data_set_period"] = ds.get("periodType", "")
        result["data_set_public_access"] = ds.get("publicAccess", "")
        
        # Check creation time
        created_str = ds.get("created", "")
        if created_str:
            created_str = created_str.replace("Z", "+00:00")
            try:
                created = datetime.fromisoformat(created_str)
                if created >= task_start:
                    result["data_set_created_after_start"] = True
            except:
                pass
                
        # Check Sharing / ACL
        accesses = ds.get("userGroupAccesses", [])
        for access in accesses:
            if access.get("id") == target_ug_id or access.get("userGroupUid") == target_ug_id:
                result["target_group_id_in_acl"] = True
                result["group_access_pattern"] = access.get("access", "")
                result["group_access_configured"] = True
                break

    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF
)

python3 -c "$PYTHON_SCRIPT" > /tmp/security_config_result.json

echo "Result saved to /tmp/security_config_result.json"
cat /tmp/security_config_result.json
echo ""
echo "=== Export Complete ==="