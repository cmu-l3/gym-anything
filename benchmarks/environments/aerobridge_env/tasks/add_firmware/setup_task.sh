#!/bin/bash
# setup_task.sh — pre_task hook for add_firmware

echo "=== Setting up add_firmware task ==="

# Source utilities for wait_for_aerobridge
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Aerobridge to be ready
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Record task start time (for anti-gaming checks)
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time.txt

# 3. Prepare Database State
#    - Create Manufacturer 'DroneCorp Avionics'
#    - Clean up any existing Firmware 4.3.7
echo "Configuring database state..."
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
    from registry.models import Manufacturer, Firmware

    # 1. Create Manufacturer
    mfr, created = Manufacturer.objects.get_or_create(
        full_name='DroneCorp Avionics',
        defaults={
            'common_name': 'DroneCorp',
            'country': 'IN',  # Using India as per Aerobridge fixtures
            'role': 0
        }
    )
    if created:
        print(f"Created manufacturer: {mfr.full_name}")
    else:
        print(f"Manufacturer already exists: {mfr.full_name}")

    # 2. Clean up existing firmware
    deleted, _ = Firmware.objects.filter(version='4.3.7').delete()
    if deleted:
        print(f"Cleaned up {deleted} existing firmware record(s) for version 4.3.7")

    # 3. Print current count
    print(f"Current firmware count: {Firmware.objects.count()}")

except Exception as e:
    print(f"Setup DB error: {e}")
PYEOF

# 4. Record initial count for anti-gaming
echo "Recording initial firmware count..."
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
from registry.models import Firmware
print(Firmware.objects.count())
" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_firmware_count.txt
echo "Initial firmware count: $INITIAL_COUNT"

# 5. Launch Firefox to Admin Panel
echo "Launching Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 1

# Clean lock files
rm -f /home/ga/.mozilla/firefox/aerobridge.profile/lock \
      /home/ga/.mozilla/firefox/aerobridge.profile/.parentlock \
      /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
      /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock

# Launch
su - ga -c "rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock; DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/' &"

sleep 8

# 6. Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="