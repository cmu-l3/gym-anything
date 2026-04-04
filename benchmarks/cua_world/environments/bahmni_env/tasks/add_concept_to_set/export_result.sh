#!/bin/bash
echo "=== Exporting add_concept_to_set results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Recover metadata
if [ -f "/tmp/concept_metadata.json" ]; then
    PANEL_UUID=$(python3 -c "import json; print(json.load(open('/tmp/concept_metadata.json'))['panel_uuid'])")
    MAGNESIUM_UUID=$(python3 -c "import json; print(json.load(open('/tmp/concept_metadata.json'))['magnesium_uuid'])")
else
    echo "ERROR: Metadata missing"
    PANEL_UUID=""
    MAGNESIUM_UUID=""
fi

# Python script to check final state
cat > /tmp/check_state.py << PYEOF
import requests
import json
import sys
from datetime import datetime

BASE_URL = "https://localhost/openmrs/ws/rest/v1"
AUTH = ("superman", "Admin123")
VERIFY_SSL = False

panel_uuid = "$PANEL_UUID"
magnesium_uuid = "$MAGNESIUM_UUID"
task_start = int("$TASK_START")

result = {
    "panel_exists": False,
    "magnesium_in_set": False,
    "modified_after_start": False,
    "current_members": []
}

if panel_uuid:
    try:
        resp = requests.get(f"{BASE_URL}/concept/{panel_uuid}", params={"v": "full"}, auth=AUTH, verify=VERIFY_SSL)
        if resp.status_code == 200:
            data = resp.json()
            result["panel_exists"] = True
            
            # Check members
            members = data.get("setMembers", [])
            member_uuids = [m["uuid"] for m in members]
            result["current_members"] = member_uuids
            
            if magnesium_uuid in member_uuids:
                result["magnesium_in_set"] = True
            
            # Check timestamp (auditInfo.dateChanged or dateCreated if new)
            # Format ex: "2024-12-15T10:00:00.000+0000"
            date_changed_str = data.get("auditInfo", {}).get("dateChanged")
            if date_changed_str:
                # Basic ISO parsing
                try:
                    # Remove timezone for simple comparison or handle properly
                    # Check for +0000 or Z
                    dt_str = date_changed_str.split('.')[0] # drop ms and tz for rough check, or use strptime
                    # Robust parsing
                    # Bahmni/OpenMRS typically returns ISO 8601
                    # We'll rely on the server having updated it recently
                    pass 
                except:
                    pass
            
            # OpenMRS API doesn't always make dateChanged easy to compare in shell, 
            # so we'll trust the verifier logic or just dump the string.
            result["date_changed"] = date_changed_str

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run check
python3 /tmp/check_state.py > /tmp/api_result.json

# Check if browser is running
APP_RUNNING="false"
if pgrep -f epiphany > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Combine results
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "api_result": $(cat /tmp/api_result.json),
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "expected_magnesium_uuid": "$MAGNESIUM_UUID"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json