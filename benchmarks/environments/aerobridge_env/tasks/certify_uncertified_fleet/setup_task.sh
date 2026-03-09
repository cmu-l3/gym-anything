#!/bin/bash
# setup_task.sh — pre_task hook for certify_uncertified_fleet
# Creates a mix of certified and uncertified aircraft to test investigation skills.

echo "=== Setting up certify_uncertified_fleet task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Aerobridge server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Prepare Database State
# We need:
# - Existing Manufacturers (Company)
# - Some valid Type Certificates
# - Some Aircraft WITH certificates (baseline compliance)
# - Some Aircraft WITHOUT certificates (the problem to fix)

cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, random
from datetime import date, timedelta

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Aircraft, Company, TypeCertificate, AircraftModel, AircraftAssembly

print("Configuring scenario data...")

# ensure we have manufacturers
manufacturers = list(Company.objects.all())
if not manufacturers:
    # Create fallback if DB is empty
    m1 = Company.objects.create(full_name="SkyDrones Inc", country="US")
    m2 = Company.objects.create(full_name="AeroDynamics", country="DE")
    manufacturers = [m1, m2]

# Ensure we have at least one valid TC
mfr = manufacturers[0]
tc, _ = TypeCertificate.objects.get_or_create(
    type_certificate_id="TC-LEGACY-001",
    defaults={
        "manufacturer": mfr,
        "valid_from": date.today() - timedelta(days=365),
        "valid_to": date.today() + timedelta(days=365)
    }
)

# Clean up existing aircraft to ensure a clean state (optional, but good for determinism)
# We won't delete everything, but we'll ensure we have our specific test cases.

# Case 1: Compliant Aircraft (Baseline)
# Ensure at least 2 compliant aircraft exist
for i in range(1, 3):
    name = f"Compliant Drone {i}"
    ac, created = Aircraft.objects.get_or_create(name=name)
    ac.manufacturer = mfr
    ac.type_certificate = tc
    ac.status = 1  # Active
    ac.save()
    print(f"Ensured compliant aircraft: {name}")

# Case 2: Non-Compliant Aircraft (The Task)
# Create 3 specific aircraft that need remediation
uncertified_names = ["Project X-1 Prototype", "Surveyor Alpha", "Cargo Lifter V2"]
for name in uncertified_names:
    ac, created = Aircraft.objects.get_or_create(name=name)
    # CRITICAL: Ensure type_certificate is None
    ac.type_certificate = None
    ac.manufacturer = random.choice(manufacturers)
    ac.status = 1
    ac.save()
    print(f"Created uncertified aircraft: {name}")

# Count uncertified
count = Aircraft.objects.filter(type_certificate__isnull=True).count()
print(f"Total uncertified aircraft: {count}")
with open("/tmp/initial_uncertified_count.txt", "w") as f:
    f.write(str(count))

PYEOF

# 3. Record Task Start Time (for anti-gaming checks)
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

# 4. Launch Firefox to Admin Login
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/"

# 5. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="