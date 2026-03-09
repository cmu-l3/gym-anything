#!/bin/bash
echo "=== Setting up Reconcile Flight Logs Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Aerobridge to be ready
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the specific data scenario using Django shell
# Scenario:
# - Aircraft A, Aircraft B
# - Plan 1 (Air A, 10:00-12:00), Plan 2 (Air B, 14:00-16:00)
# - Log 1 (Air A, 10:30) -> Orphaned, Match Plan 1
# - Log 2 (Air B, 15:00) -> Orphaned, Match Plan 2
# - Log 3 (Air A, 18:00) -> Orphaned, No Match (Outlier)

cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
from datetime import datetime, timedelta
import pytz

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Aircraft, AircraftModel, AircraftAssembly
from gcs_operations.models import FlightPlan, FlightLog

# Clean up previous run data to ensure deterministic IDs for verification logic
FlightLog.objects.filter(aircraft__name__startswith="RECON_TEST").delete()
FlightPlan.objects.filter(aircraft__name__startswith="RECON_TEST").delete()
Aircraft.objects.filter(name__startswith="RECON_TEST").delete()

# Setup Data
tz = pytz.UTC
base_time = datetime.now(tz).replace(hour=10, minute=0, second=0, microsecond=0)

# 1. Create Test Aircraft
# Ensure we have a model/assembly
model = AircraftModel.objects.first()
if not model:
    model = AircraftModel.objects.create(name="TestModel", manufacturer=None)
assembly = AircraftAssembly.objects.create(status=2, aircraft_model=model)

air_a = Aircraft.objects.create(name="RECON_TEST_A", final_assembly=assembly)
air_b = Aircraft.objects.create(name="RECON_TEST_B", final_assembly=assembly)

# 2. Create Flight Plans
# Plan 1: Air A, 10:00 - 12:00
plan_1 = FlightPlan.objects.create(
    name="RECON_PLAN_1",
    aircraft=air_a,
    start_time=base_time,
    end_time=base_time + timedelta(hours=2)
)

# Plan 2: Air B, 14:00 - 16:00
plan_2 = FlightPlan.objects.create(
    name="RECON_PLAN_2",
    aircraft=air_b,
    start_time=base_time + timedelta(hours=4),
    end_time=base_time + timedelta(hours=6)
)

# 3. Create Flight Logs (Orphaned)
# Log 1: Air A, 10:30 (Should match Plan 1)
log_1 = FlightLog.objects.create(
    aircraft=air_a,
    created_at=base_time + timedelta(minutes=30),
    flight_plan=None  # ORPHANED
)

# Log 2: Air B, 15:00 (Should match Plan 2)
log_2 = FlightLog.objects.create(
    aircraft=air_b,
    created_at=base_time + timedelta(hours=5),
    flight_plan=None  # ORPHANED
)

# Log 3: Air A, 18:00 (Outlier - No Plan covers this time)
log_3 = FlightLog.objects.create(
    aircraft=air_a,
    created_at=base_time + timedelta(hours=8),
    flight_plan=None  # ORPHANED
)

# Save IDs to a temp file for export script to use later
import json
ids = {
    "plan_1_id": plan_1.id,
    "plan_2_id": plan_2.id,
    "log_1_id": log_1.id,
    "log_2_id": log_2.id,
    "log_3_id": log_3.id
}
with open('/tmp/recon_ids.json', 'w') as f:
    json.dump(ids, f)

print(f"Created scenario data: {ids}")
PYEOF

# Create the ticket/request file
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/reconciliation_request.txt << EOF
URGENT: FLIGHT LOG RECONCILIATION NEEDED

Due to a server outage yesterday, several Flight Logs were saved without being linked to their Flight Plans.
We need to fix the database integrity before the billing cycle runs.

Please write a script to:
1. Find all Flight Logs that have no Flight Plan assigned.
2. Link them to the correct Flight Plan.
   - Match by Aircraft ID
   - Match if Log Time is between Plan Start and End Time
3. If a log cannot be matched to any plan, list its ID in /home/ga/Documents/unmatched_logs.txt

The database is SQLite at /opt/aerobridge/aerobridge.sqlite3
Django environment is at /opt/aerobridge
EOF

# Open Firefox to admin panel (helper for them to explore data models if they want)
pkill -9 -f firefox 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock
su - ga -c "DISPLAY=:1 setsid firefox --new-instance -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile 'http://localhost:8000/admin/gcs_operations/flightlog/' &"
sleep 5

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="