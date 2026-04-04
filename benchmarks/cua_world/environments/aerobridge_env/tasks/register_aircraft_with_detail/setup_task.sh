#!/bin/bash
# setup_task.sh — pre_task hook for register_aircraft_with_detail

echo "=== Setting up register_aircraft_with_detail ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ── Record task start time ────────────────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── Clean up any existing Falcon Eye 3 records (idempotent reset) ────────────
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

from registry.models import Aircraft, AircraftDetail
from gcs_operations.models import FlightOperation

# Delete Falcon Eye 3 flight operations first (FK dependency)
FlightOperation.objects.filter(name__icontains='Falcon Eye 3').delete()
# Delete aircraft detail (FK dependency)
for ac in Aircraft.objects.filter(name='Falcon Eye 3'):
    AircraftDetail.objects.filter(aircraft=ac).delete()
# Delete the aircraft itself
deleted, _ = Aircraft.objects.filter(name='Falcon Eye 3').delete()
print(f"Cleaned up: {deleted} Falcon Eye 3 records removed")
PYEOF

# ── Record baseline counts ────────────────────────────────────────────────────
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

from registry.models import Aircraft, AircraftDetail
from gcs_operations.models import FlightOperation

baseline = {
    "aircraft_count": Aircraft.objects.count(),
    "aircraft_detail_count": AircraftDetail.objects.count(),
    "flight_operation_count": FlightOperation.objects.count(),
    "existing_aircraft_names": list(Aircraft.objects.values_list('name', flat=True))
}

with open('/tmp/register_aircraft_with_detail_baseline.json', 'w') as f:
    import json
    json.dump(baseline, f, indent=2, default=str)

print(f"Baseline: {baseline['aircraft_count']} aircraft, "
      f"{baseline['aircraft_detail_count']} details, "
      f"{baseline['flight_operation_count']} operations")
PYEOF

# ── Take start screenshot ─────────────────────────────────────────────────────
DISPLAY=:1 scrot /tmp/register_aircraft_with_detail_start.png 2>/dev/null || true

# ── Launch Firefox to admin ───────────────────────────────────────────────────
wait_for_aerobridge
launch_firefox "http://localhost:8000/admin/"

echo "=== Setup complete. Task: register_aircraft_with_detail ==="
