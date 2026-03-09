#!/bin/bash
# setup_task.sh — pre_task hook for update_operator_authorizations
# Resets Electric Inspection operator to baseline state, then launches Firefox.

echo "=== Setting up update_operator_authorizations ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# ── Reset Electric Inspection to known baseline ──────────────────────────────
# operator_type=0 (NA), authorized_activities=[photographing only],
# operational_authorizations=[SORA V2 only]
echo "Resetting Electric Inspection operator to baseline state..."
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

from registry.models import Operator, Activity, Authorization

# Find Electric Inspection operator by company name
op = None
for o in Operator.objects.select_related('company').all():
    if o.company.full_name == 'Electric Inspection':
        op = o
        break

if op is None:
    print("ERROR: Electric Inspection operator not found!")
    sys.exit(1)

print(f"Found operator: {op.id} ({op.company.full_name})")

# Reset operator_type to NA (0)
op.operator_type = 0
op.save()

# Reset authorized_activities to only 'photographing'
photographing = Activity.objects.filter(name='photographing').first()
if photographing:
    op.authorized_activities.set([photographing])
    print(f"Reset authorized_activities to: [photographing]")
else:
    op.authorized_activities.clear()
    print("WARNING: photographing activity not found, cleared all")

# Reset operational_authorizations to only 'SORA V2'
sora_v2 = Authorization.objects.filter(title='SORA V2').first()
if sora_v2:
    op.operational_authorizations.set([sora_v2])
    print(f"Reset operational_authorizations to: [SORA V2]")
else:
    op.operational_authorizations.clear()
    print("WARNING: SORA V2 authorization not found, cleared all")

# Verify baseline
activities = list(op.authorized_activities.values_list('name', flat=True))
auths = list(op.operational_authorizations.values_list('title', flat=True))
print(f"Baseline set: type={op.operator_type}, activities={activities}, auths={auths}")
PYEOF

# ── Record start time and baseline state ─────────────────────────────────────
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time
echo "Task start time: $(cat /tmp/task_start_time)"

# Record baseline operator state for anti-gaming
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
from registry.models import Operator
for o in Operator.objects.select_related('company').all():
    if o.company.full_name == 'Electric Inspection':
        baseline = {
            'operator_id': str(o.id),
            'operator_type': o.operator_type,
            'activities': sorted(list(o.authorized_activities.values_list('name', flat=True))),
            'authorizations': sorted(list(o.operational_authorizations.values_list('title', flat=True)))
        }
        with open('/tmp/operator_baseline.json', 'w') as f:
            import json
            json.dump(baseline, f)
        print(f"Baseline saved: {baseline}")
        break
PYEOF

# ── Launch Firefox to admin panel ─────────────────────────────────────────────
pkill -9 -f firefox 2>/dev/null || true
sleep 1
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/' &"
sleep 6

DISPLAY=:1 scrot /tmp/update_operator_authorizations_start.png 2>/dev/null || true

echo "=== setup complete ==="
echo "Task: Update Electric Inspection operator"
echo "  (1) Add 'videotaping' to Authorized Activities"
echo "  (2) Add 'SORA' to Operational Authorizations"
echo "  (3) Change Operator Type from 'NA' to 'Non-LUC'"
echo "Admin: http://localhost:8000/admin/ | admin / adminpass123"
