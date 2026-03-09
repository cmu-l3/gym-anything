#!/bin/bash
# setup_task.sh — pre_task hook for merge_drone_operators
set -e

echo "=== Setting up merge_drone_operators task ==="

# Source task utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Aerobridge server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Record start time
record_task_start

# Prepare Database State using Python/Django
# We need to clean up previous runs and set up the specific scenario
echo "Configuring database scenario..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
import random

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Company, Aircraft, Person, AircraftModel

# 1. CLEANUP
Company.objects.filter(name__in=['Summit Drone Services', 'Valley UAV Logistics']).delete()

# 2. CREATE COMPANIES
target = Company.objects.create(name='Summit Drone Services', acronym='SDS', country='US')
source = Company.objects.create(name='Valley UAV Logistics', acronym='VUL', country='US')

# Get a generic aircraft model for the aircraft
ac_model = AircraftModel.objects.first()

# 3. CREATE TARGET ASSETS (Existing fleet for Summit)
# 2 Aircraft
for i in range(2):
    Aircraft.objects.create(
        operator=target,
        manufacturer=target, # Self-manufactured for simplicity
        nickname=f'Summit-Hawk-{i+1}',
        model=f'Hawk-{i+1}',
        status='active',
        serial_number=f'SDS-HK-{i+100}'
    )
# 1 Person
Person.objects.create(
    first_name='Summit',
    last_name='Manager',
    email='manager@summitdrones.com',
    operator=target
)

# 4. CREATE SOURCE ASSETS (To be transferred)
# 3 Aircraft
for i in range(3):
    Aircraft.objects.create(
        operator=source,
        manufacturer=source,
        nickname=f'Valley-Scout-{i+1}',
        model=f'Scout-{i+1}',
        status='active',
        serial_number=f'VUL-SC-{i+100}'
    )
# 2 Persons
Person.objects.create(
    first_name='Valley',
    last_name='Pilot1',
    email='pilot1@valleyuav.com',
    operator=source
)
Person.objects.create(
    first_name='Valley',
    last_name='Technician',
    email='tech@valleyuav.com',
    operator=source
)

print(f"Setup Complete.")
print(f"Target (Summit): {Aircraft.objects.filter(operator=target).count()} aircraft, {Person.objects.filter(operator=target).count()} people")
print(f"Source (Valley): {Aircraft.objects.filter(operator=source).count()} aircraft, {Person.objects.filter(operator=source).count()} people")
PYEOF

# Launch Firefox to the Companies list to start
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/registry/company/"

# Take initial screenshot
sleep 5
take_screenshot "/tmp/task_initial.png"

echo "=== Task setup complete ==="