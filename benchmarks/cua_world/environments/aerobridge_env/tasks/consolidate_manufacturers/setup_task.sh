#!/bin/bash
# setup_task.sh — pre_task hook for consolidate_manufacturers
# Sets up the database with duplicate manufacturers and aircraft linked to them.

echo "=== Setting up consolidate_manufacturers task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Record task start
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

# Setup Database State
echo "Injecting scenario data..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
import random

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
# Load env vars manually if needed, though sourcing in bash usually works
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))

django.setup()

from registry.models import Company, Aircraft, AircraftModel, Operator

# 1. Ensure Manufacturers exist
canonical, _ = Company.objects.get_or_create(full_name="Yuneec International", defaults={"country": "CN"})
dup1, _ = Company.objects.get_or_create(full_name="Yuneec", defaults={"country": "CN"})
dup2, _ = Company.objects.get_or_create(full_name="Yuneec Electric", defaults={"country": "CN"})

print(f"Manufacturers prepared: {canonical.id} (Canonical), {dup1.id}, {dup2.id}")

# 2. Ensure we have an Operator (needed for Aircraft)
operator, _ = Operator.objects.get_or_create(name="Test Fleet Ops")

# 3. Create/Reset Test Aircraft
# We need specific aircraft to track. We'll use specific names/registrations.
# If they exist, update them to point to the DUPLICATES to start the task.

# Aircraft A -> Yuneec (Duplicate 1)
ac_a, _ = Aircraft.objects.get_or_create(
    name="Typhoon H - Unit A",
    defaults={
        "operator": operator,
        "status": "active",
        "flight_controller_id": "TYPH-A-001"
    }
)
ac_a.manufacturer = dup1
ac_a.save()

# Aircraft B -> Yuneec Electric (Duplicate 2)
ac_b, _ = Aircraft.objects.get_or_create(
    name="Breeze 4K - Unit B",
    defaults={
        "operator": operator,
        "status": "active",
        "flight_controller_id": "BRZ-B-002"
    }
)
ac_b.manufacturer = dup2
ac_b.save()

# Aircraft C -> Yuneec International (Already correct, shouldn't change)
ac_c, _ = Aircraft.objects.get_or_create(
    name="Mantis Q - Unit C",
    defaults={
        "operator": operator,
        "status": "active",
        "flight_controller_id": "MNT-C-003"
    }
)
ac_c.manufacturer = canonical
ac_c.save()

print(f"Test Aircraft Setup:")
print(f"  {ac_a.name} -> {ac_a.manufacturer.full_name}")
print(f"  {ac_b.name} -> {ac_b.manufacturer.full_name}")
print(f"  {ac_c.name} -> {ac_c.manufacturer.full_name}")

# Save IDs for verification
with open("/tmp/setup_ids.txt", "w") as f:
    f.write(f"{ac_a.id},{ac_b.id},{ac_c.id}\n")
    f.write(f"{canonical.id}\n")

# Count total aircraft for data loss prevention check
print(f"Total Aircraft Count: {Aircraft.objects.count()}")
PYEOF

# Store initial total count for later comparison
AIRCRAFT_COUNT_INITIAL=$(django_query "from registry.models import Aircraft; print(Aircraft.objects.count())")
echo "$AIRCRAFT_COUNT_INITIAL" > /tmp/aircraft_count_initial

# Launch Firefox
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/registry/aircraft/"

# Screenshot
take_screenshot /tmp/consolidate_manufacturers_start.png

echo "=== Setup complete ==="