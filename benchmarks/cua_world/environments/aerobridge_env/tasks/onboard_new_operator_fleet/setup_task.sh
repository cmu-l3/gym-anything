#!/bin/bash
# setup_task.sh — pre_task hook for onboard_new_operator_fleet

echo "=== Setting up onboard_new_operator_fleet ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# ── Clean up any previous attempt records (idempotent reset) ─────────────────
echo "Cleaning up previous attempt records..."
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

from gcs_operations.models import FlightOperation, FlightPlan
from registry.models import (Aircraft, AircraftAssembly, AircraftModel,
                              Pilot, Contact, Person, Operator, Company)

# Delete in reverse dependency order
del_fo = FlightOperation.objects.filter(name='HA Fleet Certification Flight').delete()[0]
del_fp = FlightPlan.objects.filter(name='Mumbai Harbor Survey').delete()[0]
del_ac = Aircraft.objects.filter(name__startswith='HA-Scout-').delete()[0]

# Delete pilots/contacts linked to Horizon Aerial operator
horizon_companies = Company.objects.filter(full_name='Horizon Aerial Services Pvt Ltd')
for comp in horizon_companies:
    ops = Operator.objects.filter(company=comp)
    for op in ops:
        Pilot.objects.filter(operator=op).delete()
        Contact.objects.filter(operator=op).delete()
        op.authorized_activities.clear()
        op.operational_authorizations.clear()
    ops.delete()
del_comp = horizon_companies.delete()[0]

# Delete persons by email domain
del_persons = Person.objects.filter(email__endswith='@horizonaerial.in').delete()[0]

# Clean up unassigned assemblies for Horizon Surveyor X1 model
try:
    model = AircraftModel.objects.get(popular_name='Horizon Surveyor X1')
    del_asm = AircraftAssembly.objects.filter(
        aircraft_model=model, aircraft__isnull=True
    ).delete()[0]
    print(f"Cleaned {del_asm} stale assemblies")
except AircraftModel.DoesNotExist:
    pass

print(f"Cleanup: {del_comp} companies, {del_persons} persons, "
      f"{del_ac} aircraft, {del_fo} operations, {del_fp} plans")
PYEOF

# ── Delete stale output files BEFORE recording timestamp ─────────────────────
rm -f /tmp/onboard_new_operator_fleet_result.json
rm -f /tmp/onboard_fleet_baseline.json
rm -f /tmp/onboard_new_operator_fleet_start.png
rm -f /tmp/onboard_new_operator_fleet_end.png

# ── Record task start time ───────────────────────────────────────────────────
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

# ── Pre-create AircraftModel + 2 Complete assemblies ─────────────────────────
# (Avoids known AircraftModel admin form bug in registry/forms.py)
echo "Pre-creating AircraftModel and assemblies..."
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

from registry.models import AircraftModel, AircraftAssembly, TypeCertificate, Firmware

tc = TypeCertificate.objects.first()
fw = Firmware.objects.first()

model, created = AircraftModel.objects.get_or_create(
    popular_name='Horizon Surveyor X1',
    defaults={
        'name': 'Horizon Surveyor X1',
        'category': 2,        # ROTORCRAFT
        'sub_category': 1,    # Multirotor
        'series': '2025.1',
        'mass': 2500,
        'max_certified_takeoff_weight': 3.000,
        'max_speed': 18,
        'type_certificate': tc,
        'firmware': fw,
    }
)
if not model.name:
    model.name = 'Horizon Surveyor X1'
    model.save(update_fields=['name'])
action = "Created" if created else "Already exists"
print(f"{action} AircraftModel: {model.popular_name} (pk={model.pk})")

# Create 2 fresh unassigned Complete assemblies
for i in range(1, 3):
    asm = AircraftAssembly.objects.create(
        aircraft_model=model,
        status=2    # Complete
    )
    print(f"Created AircraftAssembly pk={asm.pk} (status=Complete)")

total = AircraftAssembly.objects.filter(
    aircraft_model=model, aircraft__isnull=True
).count()
print(f"Unassigned assemblies for Horizon Surveyor X1: {total}")
PYEOF

# ── Record baseline counts ───────────────────────────────────────────────────
echo "Recording baseline counts..."
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

from registry.models import Company, Operator, Person, Pilot, Aircraft
from gcs_operations.models import FlightPlan, FlightOperation

baseline = {
    'companies': Company.objects.count(),
    'operators': Operator.objects.count(),
    'persons': Person.objects.count(),
    'pilots': Pilot.objects.count(),
    'aircraft': Aircraft.objects.count(),
    'flight_plans': FlightPlan.objects.count(),
    'flight_operations': FlightOperation.objects.count(),
}
with open('/tmp/onboard_fleet_baseline.json', 'w') as f:
    json.dump(baseline, f, indent=2)
print(f"Baseline: {json.dumps(baseline)}")
PYEOF

# ── Launch Firefox to admin ──────────────────────────────────────────────────
launch_firefox "http://localhost:8000/admin/"

DISPLAY=:1 scrot /tmp/onboard_new_operator_fleet_start.png 2>/dev/null || true

echo "=== Setup complete. Task: onboard_new_operator_fleet ==="
echo "Admin: http://localhost:8000/admin/ | admin / adminpass123"
