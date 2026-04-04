#!/bin/bash
# setup_task.sh — pre_task hook for register_aircraft_model_chain

echo "=== Setting up register_aircraft_model_chain ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# ── Clean up any pre-existing test records ────────────────────────────────────
echo "Cleaning up pre-existing Nile Scout 200 records..."
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

from registry.models import Aircraft, AircraftAssembly, AircraftModel

# Delete in dependency order: Aircraft → AircraftAssembly → AircraftModel
ac_del = Aircraft.objects.filter(name='NS-001').delete()[0]

# Delete assemblies for Nile Scout 200 model
model_ids = list(AircraftModel.objects.filter(name='Nile Scout 200').values_list('id', flat=True))
if model_ids:
    aa_del = AircraftAssembly.objects.filter(aircraft_model_id__in=model_ids).delete()[0]
else:
    aa_del = 0

am_del = AircraftModel.objects.filter(name='Nile Scout 200').delete()[0]
print(f"Deleted: {ac_del} aircraft, {aa_del} assemblies, {am_del} models")

print(f"Current AircraftModel count: {AircraftModel.objects.count()}")
print(f"Current AircraftAssembly count: {AircraftAssembly.objects.count()}")
print(f"Current Aircraft count: {Aircraft.objects.count()}")
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
from registry.models import Aircraft, AircraftAssembly, AircraftModel
baseline = {
    'model_count': AircraftModel.objects.count(),
    'assembly_count': AircraftAssembly.objects.count(),
    'aircraft_count': Aircraft.objects.count()
}
with open('/tmp/aircraft_chain_baseline.json', 'w') as f:
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

DISPLAY=:1 scrot /tmp/register_aircraft_model_chain_start.png 2>/dev/null || true

echo "=== setup complete ==="
echo "Task: Create AircraftModel 'Nile Scout 200' -> AircraftAssembly -> Aircraft 'NS-001'"
echo "Admin: http://localhost:8000/admin/ | admin / adminpass123"
