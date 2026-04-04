#!/bin/bash
# setup_task.sh — pre_task hook for change_admin_password
# Resets admin password to known state, records initial hash, launches browser

set -e
echo "=== Setting up change_admin_password task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Aerobridge server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Reset admin password to 'adminpass123' to ensure consistent starting state
echo "Resetting admin password to start state..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
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

try:
    from django.contrib.auth.models import User
    u = User.objects.get(username='admin')
    u.set_password('adminpass123')
    u.save()
    print(f"Admin password reset. Hash: {u.password[:20]}...")
    
    # Save initial hash for comparison later
    with open('/tmp/initial_password_hash.txt', 'w') as f:
        f.write(u.password)
except Exception as e:
    print(f"Setup error: {e}")
PYEOF

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Launch Firefox to Admin Login
echo "Launching Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 1

# Clear profile locks
rm -f /home/ga/.mozilla/firefox/aerobridge.profile/lock \
       /home/ga/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock

# Launch
su - ga -c "rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock; DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Target: Change admin password to 'SecureDrone2024!'"