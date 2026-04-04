#!/bin/bash
# setup_task.sh - Prepare environment for archive_historical_flight_plans
set -e

echo "=== Setting up archive_historical_flight_plans task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Aerobridge to be ready
wait_for_aerobridge 60 || echo "WARNING: Aerobridge server may not be ready"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Inject test data using Python/Django
# We need a mix of pre-2024 (to be archived) and post-2024 (to be kept) plans.
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

echo "Injecting flight plan data..."
/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
import pytz
from datetime import datetime, timedelta

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

# Try to import FlightPlan from likely apps
FlightPlan = None
try:
    from flight_passport.models import FlightPlan
    print("Using flight_passport.models.FlightPlan")
except ImportError:
    try:
        from gcs_operations.models import FlightPlan
        print("Using gcs_operations.models.FlightPlan")
    except ImportError:
        print("ERROR: Could not find FlightPlan model")
        sys.exit(1)

# Also need Aircraft and Person for foreign keys
from registry.models import Aircraft, Person

# Get dependencies
aircraft = Aircraft.objects.first()
if not aircraft:
    print("Creating dummy aircraft...")
    aircraft = Aircraft.objects.create(name="Test Drone", status="active")

pilot = Person.objects.first()
if not pilot:
    print("Creating dummy pilot...")
    pilot = Person.objects.create(first_name="Test", last_name="Pilot")

# Clear existing flight plans to ensure clean state for verification
print(f"Clearing {FlightPlan.objects.count()} existing flight plans...")
FlightPlan.objects.all().delete()

# Helper to create plan
def create_fp(name, date_str):
    # Parse date (assume UTC)
    dt = pytz.utc.localize(datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S"))
    fp = FlightPlan.objects.create(
        name=name,
        start_time=dt,
        end_time=dt + timedelta(hours=2),
        aircraft=aircraft,
        pilot=pilot
    )
    return fp

# Create HISTORICAL records (Target for Archive)
h1 = create_fp("History Alpha 2022", "2022-06-15 10:00:00")
h2 = create_fp("History Beta 2023", "2023-11-20 09:00:00")
h3 = create_fp("History Gamma 2023", "2023-12-31 23:59:59") # Edge case

# Create ACTIVE records (Should Remain)
a1 = create_fp("Active Delta 2024", "2024-01-01 00:00:01") # Edge case
a2 = create_fp("Active Epsilon 2025", "2025-05-20 14:00:00")

print("Data injection complete.")
print(f"Total Plans: {FlightPlan.objects.count()}")

# Save expected IDs to a file for the export script to check against
import json
expected_data = {
    "historical_ids": [h1.pk, h2.pk, h3.pk],
    "historical_names": [h1.name, h2.name, h3.name],
    "active_ids": [a1.pk, a2.pk],
    "active_names": [a1.name, a2.name]
}
with open('/tmp/expected_flight_data.json', 'w') as f:
    json.dump(expected_data, f)

PYEOF

# Clean up any previous archive file
rm -f /home/ga/archive_pre2024.json

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="