#!/bin/bash
# export_result.sh — post_task hook for change_admin_password
# Verifies password change using Django ORM

echo "=== Exporting change_admin_password result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get timestamps and initial data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_HASH=$(cat /tmp/initial_password_hash.txt 2>/dev/null || echo "")

# 3. Verify password status using Django
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os, sys, django, json
from django.contrib.auth import authenticate

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
# Load env vars
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_hash": "$INITIAL_HASH",
    "current_hash": "",
    "hash_changed": False,
    "new_password_works": False,
    "old_password_works": False,
    "user_active": False,
    "is_superuser": False
}

try:
    from django.contrib.auth.models import User
    
    # Get admin user
    try:
        u = User.objects.get(username='admin')
        result["current_hash"] = u.password
        result["user_active"] = u.is_active
        result["is_superuser"] = u.is_superuser
        
        # Check if hash changed
        if result["initial_hash"] and u.password != result["initial_hash"]:
            result["hash_changed"] = True
            
        # Check passwords
        # We use check_password directly on the user object
        result["new_password_works"] = u.check_password('SecureDrone2024!')
        result["old_password_works"] = u.check_password('adminpass123')
        
        print(f"Hash changed: {result['hash_changed']}")
        print(f"New password works: {result['new_password_works']}")
        print(f"Old password works: {result['old_password_works']}")

    except User.DoesNotExist:
        print("CRITICAL: Admin user not found!")
        result["error"] = "Admin user deleted"

except Exception as e:
    print(f"Export error: {e}")
    result["error"] = str(e)

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# 4. Handle permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="