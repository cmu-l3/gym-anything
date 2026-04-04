#!/bin/bash
# setup_task.sh — pre_task hook for process_warranty_replacement

echo "=== Setting up process_warranty_replacement task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Aerobridge to be ready
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Record task start time
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

# Setup the specific scenario data
echo "Creating crashed aircraft and dependencies..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Aircraft, Company, Manufacturer, AircraftModel, AircraftAssembly

# 1. Ensure Manufacturer exists
mfg, _ = Manufacturer.objects.get_or_create(name='DroneCorp Global')

# 2. Ensure Operator exists
op, _ = Company.objects.get_or_create(name='SkyHigh Services', defaults={'country': 'US'})

# 3. Setup the "Crashed" Aircraft
# Delete if exists to reset state
Aircraft.objects.filter(registration__startswith='SH-CRASH-001').delete()
Aircraft.objects.filter(registration='SH-REPL-002').delete()

# We need a valid model and assembly for the aircraft
# Aerobridge often requires these foreign keys
model, _ = AircraftModel.objects.get_or_create(name='Sentinel-X', defaults={'manufacturer': mfg})

# Create an assembly if needed (some versions of Aerobridge might require it)
# We'll try to create the aircraft without it first, or with defaults if nullable
# Inspecting models usually reveals 'status' is a field.

crashed_aircraft = Aircraft.objects.create(
    registration='SH-CRASH-001',
    manufacturer=mfg,
    operator=op,
    model=model,
    status='active', # Assuming status field exists and takes string or int
)

print(f"Created crashed aircraft: {crashed_aircraft.registration}")
print(f"  Operator: {op.name}")
print(f"  Manufacturer: {mfg.name}")

# Record IDs for verification later if needed
with open('/tmp/setup_ids.txt', 'w') as f:
    f.write(f"OP_ID={op.pk}\n")
    f.write(f"MFR_ID={mfg.pk}\n")

PYEOF

# Launch Firefox to the Aircraft Registry list
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/registry/aircraft/"

# Wait for window and maximize
sleep 5
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="