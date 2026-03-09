#!/bin/bash
# export_result.sh — post_task hook for assign_user_permissions
# Exports the permissions of the 'coordinator' user for verification.

echo "=== Exporting assign_user_permissions result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/assign_permissions_final.png

# Capture task timing
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Query Django DB for user details
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os, sys, django, json

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

result = {
    "task_start": int('${TASK_START}' or 0),
    "task_end": int('${TASK_END}' or 0),
    "user_exists": False,
    "is_staff": False,
    "is_superuser": False,
    "group_count": 0,
    "permissions": [],
    "permission_count": 0
}

try:
    from django.contrib.auth.models import User
    
    user = User.objects.filter(username='coordinator').first()
    
    if user:
        result["user_exists"] = True
        result["is_staff"] = user.is_staff
        result["is_superuser"] = user.is_superuser
        result["group_count"] = user.groups.count()
        
        # Get all permissions assigned directly to user
        # Format: "app_label.codename"
        perms = user.user_permissions.all().select_related('content_type')
        perm_list = [f"{p.content_type.app_label}.{p.codename}" for p in perms]
        
        result["permissions"] = perm_list
        result["permission_count"] = len(perm_list)
        
    print(f"Exported data for user 'coordinator': {result['permission_count']} permissions")

except Exception as e:
    result["error"] = str(e)
    print(f"Export Error: {e}")

# Save to temp file first
with open('/tmp/export_data.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/export_data.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f /tmp/export_data.json

echo "=== Export complete ==="