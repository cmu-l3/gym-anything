#!/bin/bash
# setup_task.sh — Prepares DB with missing data and creates CSV input

echo "=== Setting up bulk_update_aircraft_specs task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Aerobridge to be ready
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Record start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Generate the Datasheet CSV
# ============================================================
cat > /home/ga/manufacturer_datasheet.csv << EOF
Model_Name,Weight_Grams,Notes
Mavic 2 Pro,907,Consumer Line
Autel Evo II,1150,Enterprise Line
Parrot Anafi,320,Thermal variant available
EOF
chown ga:ga /home/ga/manufacturer_datasheet.csv

echo "Created /home/ga/manufacturer_datasheet.csv"

# ============================================================
# 2. Reset Database State
#    - Clear existing aircraft
#    - Create target aircraft with mass=0
#    - Create distractor aircraft with correct mass (should not change)
# ============================================================
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
import django
django.setup()

from registry.models import Aircraft

# Clear existing for clean state
Aircraft.objects.all().delete()
print("Cleared existing aircraft registry.")

# Create Targets (Mass = 0 needs update)
targets = ["Mavic 2 Pro", "Autel Evo II", "Parrot Anafi"]
for name in targets:
    Aircraft.objects.create(
        name=name,
        mass=0.0,
        status='active',
        flight_controller_id=f"FC-{name.replace(' ', '')[:5].upper()}"
    )
    print(f"Created target: {name} (mass=0.0)")

# Create Distractor (Should not be touched)
Aircraft.objects.create(
    name="Custom Heavy Lifter",
    mass=25.5,
    status='active',
    flight_controller_id="FC-CUSTOM-001"
)
print("Created distractor: Custom Heavy Lifter (mass=25.5)")

PYEOF

# ============================================================
# 3. Setup Environment
# ============================================================
# Ensure terminal is ready
# (Nothing specific needed beyond standard env)

echo "=== Setup Complete ==="