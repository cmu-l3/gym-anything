#!/bin/bash
# setup_task.sh — pre_task hook for add_operator_company

echo "=== Setting up add_operator_company task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Ensure Aerobridge server is ready
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Clean up any previous attempts (remove 'Vayupath' companies)
echo "Cleaning up previous 'Vayupath' records..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
# Load env vars manually if needed
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

try:
    from registry.models import Company
    # Delete by full name or common name
    qs = Company.objects.filter(full_name__icontains='Vayupath') | Company.objects.filter(common_name__icontains='Vayupath')
    count, _ = qs.delete()
    print(f"Deleted {count} existing 'Vayupath' records")
except Exception as e:
    print(f"Cleanup error: {e}")
PYEOF

# 3. Record task start time and initial count for anti-gaming
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

INITIAL_COUNT=$(/opt/aerobridge_venv/bin/python3 -c "
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip(\"'\").strip('\"'))
django.setup()
from registry.models import Company
print(Company.objects.count())
" 2>/dev/null || echo "0")

echo "$INITIAL_COUNT" > /tmp/initial_company_count
echo "Initial Company count: $INITIAL_COUNT"

# 4. Launch Firefox to Admin Login
echo "Launching Firefox..."
# Kill existing
pkill -9 -f firefox 2>/dev/null || true
sleep 1
# Clean locks
rm -f /home/ga/.mozilla/firefox/aerobridge.profile/lock \
       /home/ga/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock

# Launch
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/' &"

# Wait for window
sleep 8
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="