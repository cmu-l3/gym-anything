#!/bin/bash
# setup_task.sh — pre_task hook for create_flight_operation

echo "=== Setting up create_flight_operation task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Remove any pre-existing test flight operation
echo "Removing any pre-existing 'Rajasthan Corridor Inspection' operation..."
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
    from gcs_operations.models import FlightOperation
    deleted = 0
    for name_field in ['name', 'operation_name', 'description', 'flight_operation_name']:
        try:
            qs = FlightOperation.objects.filter(
                **{name_field: 'Rajasthan Corridor Inspection'}
            )
            count, _ = qs.delete()
            deleted += count
        except Exception:
            pass
    if deleted:
        print(f"Removed {deleted} existing test operation(s)")
    else:
        print("No pre-existing test operation found (clean)")
    print(f"Current flight operation count: {FlightOperation.objects.count()}")
except Exception as e:
    print(f"Cleanup note: {e}")
PYEOF

date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

FO_COUNT_BEFORE=$(/opt/aerobridge_venv/bin/python3 -c "
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
try:
    from gcs_operations.models import FlightOperation
    print(FlightOperation.objects.count())
except Exception:
    print('0')
" 2>/dev/null || echo "0")
echo "$FO_COUNT_BEFORE" > /tmp/flightoperation_count_before
echo "Flight operation count before task: ${FO_COUNT_BEFORE}"

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

DISPLAY=:1 scrot /tmp/create_flight_operation_start.png 2>/dev/null || true

echo "=== create_flight_operation task setup complete ==="
echo "Task: Create flight operation 'Rajasthan Corridor Inspection'"
echo "Admin URL: http://localhost:8000/admin/"
echo "Login: admin / adminpass123"
echo "Note: Pre-loaded aircraft: 'F1 #1', 'F1 #2' (from real Aerobridge fixture data)"
