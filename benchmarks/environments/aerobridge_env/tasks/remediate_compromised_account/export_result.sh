#!/bin/bash
# export_result.sh - Post-task verification data extraction

echo "=== Exporting Remediate Compromised Account Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Ground Truth Victim
VICTIM_USER=$(cat /tmp/ground_truth_victim.txt 2>/dev/null || echo "")
echo "Ground Truth Victim: $VICTIM_USER"

# 3. Check Report File
REPORT_PATH="/home/ga/Documents/incident_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -n 1 | tr -d '\n')
    echo "Report found: '$REPORT_CONTENT'"
else
    echo "Report file not found."
fi

# 4. Query Database for User Status
# We need to check:
# - Victim status (Should be INACTIVE / False)
# - Other users status (Should be ACTIVE / True)
# - Admin status (Should be ACTIVE / True)

cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os
import sys
import django
import json

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from django.contrib.auth.models import User

victim_username = "${VICTIM_USER}"
report_exists = "${REPORT_EXISTS}" == "true"
report_content = "${REPORT_CONTENT}"

result = {
    "victim_username": victim_username,
    "report_exists": report_exists,
    "report_content": report_content,
    "victim_is_active": True, # Default to bad state
    "innocent_users_active": True,
    "admin_active": True,
    "users_status": {}
}

try:
    # Check Victim
    if victim_username:
        try:
            v_user = User.objects.get(username=victim_username)
            result["victim_is_active"] = v_user.is_active
            result["users_status"][victim_username] = v_user.is_active
        except User.DoesNotExist:
            print(f"Error: Victim user {victim_username} not found in DB")

    # Check Admin
    try:
        admin = User.objects.get(username='admin')
        result["admin_active"] = admin.is_active
    except:
        pass

    # Check Innocents
    others = ['ops_manager', 'flight_lead', 'logistics_coord']
    all_others_active = True
    for u in others:
        if u == victim_username:
            continue
        try:
            user = User.objects.get(username=u)
            result["users_status"][u] = user.is_active
            if not user.is_active:
                all_others_active = False
        except:
            pass
    
    result["innocent_users_active"] = all_others_active

except Exception as e:
    print(f"Error checking DB: {e}")
    result["error"] = str(e)

# Write Result JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("DB Check Complete.")
PYEOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json