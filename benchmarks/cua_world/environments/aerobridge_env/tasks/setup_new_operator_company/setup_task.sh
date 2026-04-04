#!/bin/bash
# setup_task.sh — pre_task hook for setup_new_operator_company

echo "=== Setting up setup_new_operator_company ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# ── Clean up any pre-existing BlueSky records ─────────────────────────────────
echo "Cleaning up pre-existing BlueSky records..."
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

from registry.models import Company, Operator

# Delete operators linked to BlueSky first (FK dependency)
bluesky_companies = Company.objects.filter(full_name='BlueSky Robotics Pvt Ltd')
for comp in bluesky_companies:
    op_del = Operator.objects.filter(company=comp).delete()[0]
    print(f"  Deleted {op_del} operator(s) for BlueSky")

comp_del = bluesky_companies.delete()[0]
print(f"  Deleted {comp_del} BlueSky company record(s)")

print(f"Current Company count: {Company.objects.count()}")
print(f"Current Operator count: {Operator.objects.count()}")
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
from registry.models import Company, Operator
baseline = {
    'company_count': Company.objects.count(),
    'operator_count': Operator.objects.count()
}
with open('/tmp/operator_company_baseline.json', 'w') as f:
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

DISPLAY=:1 scrot /tmp/setup_new_operator_company_start.png 2>/dev/null || true

echo "=== setup complete ==="
echo "Task: Create Company 'BlueSky Robotics Pvt Ltd' + Operator with M2M"
echo "Admin: http://localhost:8000/admin/ | admin / adminpass123"
