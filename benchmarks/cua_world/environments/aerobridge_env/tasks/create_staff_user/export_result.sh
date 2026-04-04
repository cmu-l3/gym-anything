#!/bin/bash
# export_result.sh — post_task hook for create_staff_user

echo "=== Exporting create_staff_user result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/create_staff_user_final.png 2>/dev/null || true

# 2. Get task context
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")
COUNT_BEFORE=$(cat /tmp/user_count_before 2>/dev/null || echo "0")

# 3. Query Django Database
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os, sys, django, json
from datetime import datetime

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
try:
    with open('/opt/aerobridge/.env') as f:
        for line in f:
            line = line.strip()
            if '=' in line and not line.startswith('#'):
                k, _, v = line.partition('=')
                os.environ.setdefault(k, v.strip("'").strip('"'))
except:
    pass
django.setup()

result = {
    "task_start_time": "${TASK_START}",
    "count_before": int("${COUNT_BEFORE}" or 0),
    "current_count": 0,
    "user_found": False,
    "user_data": {},
    "password_valid": False,
    "error": None
}

try:
    from django.contrib.auth.models import User
    
    result["current_count"] = User.objects.count()
    
    # Check for the specific user
    try:
        user = User.objects.get(username='ops_coordinator')
        result["user_found"] = True
        
        # Collect user data for verification
        result["user_data"] = {
            "username": user.username,
            "first_name": user.first_name,
            "last_name": user.last_name,
            "email": user.email,
            "is_staff": user.is_staff,
            "is_superuser": user.is_superuser,
            "is_active": user.is_active,
            "date_joined": str(user.date_joined)
        }
        
        # Verify password (critical for authentication tasks)
        if user.check_password('FlightOps2024!'):
            result["password_valid"] = True
            
    except User.DoesNotExist:
        result["user_found"] = False

except Exception as e:
    result["error"] = str(e)
    print(f"Error querying database: {e}")

# Save result
with open('/tmp/create_staff_user_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result exported to /tmp/create_staff_user_result.json")
PYEOF

# 4. Handle permissions so verification host can read it (if needed)
chmod 644 /tmp/create_staff_user_result.json 2>/dev/null || true

echo "=== Export complete ==="