#!/bin/bash
# setup_task.sh — pre_task hook for add_manufacturer

echo "=== Setting up add_manufacturer task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Remove any pre-existing test manufacturer
echo "Removing any pre-existing 'SkyTech Innovations' manufacturer..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()
try:
    from registry.models import Company
    deleted, _ = Company.objects.filter(full_name='SkyTech Innovations').delete()
    if deleted:
        print(f"Removed {deleted} existing 'SkyTech Innovations' company record(s)")
    else:
        print("No pre-existing 'SkyTech Innovations' found (clean)")
    print(f"Current company count: {Company.objects.count()}")
except Exception as e:
    print(f"Cleanup note: {e}")
PYEOF

date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

MFR_COUNT_BEFORE=$(/opt/aerobridge_venv/bin/python3 -c "
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
echo "$MFR_COUNT_BEFORE" > /tmp/manufacturer_count_before
echo "Company count before task: ${MFR_COUNT_BEFORE}"

pkill -9 -f firefox 2>/dev/null || true
for i in $(seq 1 20); do pgrep -f firefox > /dev/null 2>&1 || break; sleep 0.5; done
sleep 1
rm -f /home/ga/.mozilla/firefox/aerobridge.profile/lock \
       /home/ga/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock
su - ga -c "rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock; DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/' &"
sleep 6

DISPLAY=:1 scrot /tmp/add_manufacturer_start.png 2>/dev/null || true

echo "=== add_manufacturer task setup complete ==="
echo "Task: Add manufacturer 'SkyTech Innovations' (country: India/IN)"
echo "Admin URL: http://localhost:8000/admin/"
echo "Login: admin / adminpass123"
