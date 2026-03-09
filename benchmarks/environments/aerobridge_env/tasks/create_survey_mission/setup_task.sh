#!/bin/bash
# setup_task.sh — pre_task hook for create_survey_mission

echo "=== Setting up create_survey_mission ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# ── Clean up any pre-existing test records ────────────────────────────────────
echo "Cleaning up pre-existing test records..."
/opt/aerobridge_venv/bin/python3 << 'PYEOF'
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ['DJANGO_SETTINGS_MODULE'] = 'aerobridge.settings'
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

from gcs_operations.models import FlightPlan, FlightOperation

# Delete any pre-existing Kolkata records
ops_deleted = FlightOperation.objects.filter(name='Kolkata Port Inspection').delete()[0]
plans_deleted = FlightPlan.objects.filter(name='Kolkata Port Survey').delete()[0]
print(f"Deleted {ops_deleted} pre-existing operation(s), {plans_deleted} plan(s)")

print(f"Current FlightPlan count: {FlightPlan.objects.count()}")
print(f"Current FlightOperation count: {FlightOperation.objects.count()}")
PYEOF

# ── Record start time and baseline counts ─────────────────────────────────────
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

/opt/aerobridge_venv/bin/python3 << 'PYEOF'
import os, sys, django, json
sys.path.insert(0, '/opt/aerobridge')
os.environ['DJANGO_SETTINGS_MODULE'] = 'aerobridge.settings'
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()
from gcs_operations.models import FlightPlan, FlightOperation

baseline = {
    'fp_count': FlightPlan.objects.count(),
    'fo_count': FlightOperation.objects.count(),
    'existing_plan_id': str(FlightPlan.objects.filter(name='Flight Plan A').values_list('id', flat=True).first() or '')
}
with open('/tmp/survey_mission_baseline.json', 'w') as f:
    json.dump(baseline, f)
print(f"Baseline: {baseline}")
PYEOF

# ── Launch Firefox ─────────────────────────────────────────────────────────────
pkill -9 -f firefox 2>/dev/null || true
sleep 1
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/' &"
sleep 6

DISPLAY=:1 scrot /tmp/create_survey_mission_start.png 2>/dev/null || true

echo "=== setup complete ==="
echo "Task: Create FlightPlan 'Kolkata Port Survey' then FlightOperation 'Kolkata Port Inspection'"
echo "Admin: http://localhost:8000/admin/ | admin / adminpass123"
