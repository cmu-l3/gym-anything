#!/bin/bash
# setup_task.sh — pre_task hook for create_staff_user

echo "=== Setting up create_staff_user task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Aerobridge server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Clean up: Remove target user if it already exists
echo "Ensuring clean state (removing 'ops_coordinator' if exists)..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
# Load env vars manually if source failed (redundancy)
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

try:
    from django.contrib.auth.models import User
    # Delete if exists
    count, _ = User.objects.filter(username='ops_coordinator').delete()
    if count > 0:
        print(f"Removed existing 'ops_coordinator' user.")
    else:
        print("User 'ops_coordinator' not found (clean state).")
    
    print(f"Current user count: {User.objects.count()}")
except Exception as e:
    print(f"Setup error: {e}")
PYEOF

# 3. Record baseline for anti-gaming
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time
record_count "django.contrib.auth.models" "User" > /tmp/user_count_before

# 4. Launch Firefox to Admin Login
echo "Launching Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 1

# Clear lock files that might prevent Firefox from starting
rm -f /home/ga/.mozilla/firefox/aerobridge.profile/lock \
      /home/ga/.mozilla/firefox/aerobridge.profile/.parentlock \
      /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
      /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock

# Launch using the configured profile
su - ga -c "rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
    /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock; \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/' &"

# Wait for window and maximize
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -i -a "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/create_staff_user_initial.png

echo "=== Setup complete ==="