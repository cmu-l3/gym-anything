#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Setting up resolve_orphaned_flight_plans task ==="

# 1. Wait for Aerobridge server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Setup Scenario Data (Companies, Pilots, Orphaned Flight Plans)
echo "Creating scenario data..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os
import sys
import django
from datetime import datetime, timedelta
import random

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Company, Person
try:
    from gcs_operations.models import FlightPlan
except ImportError:
    try:
        from flight_plans.models import FlightPlan
    except ImportError:
        print("CRITICAL: Could not import FlightPlan model")
        sys.exit(1)

# Clean up any existing scenario data to ensure fresh state
print("Cleaning up old scenario data...")
FlightPlan.objects.filter(callsign__startswith='MIG-ERR-').delete()
Company.objects.filter(full_name__in=['SkyHigh Services', 'AgriDrones Inc']).delete()
# Note: Cascading delete might remove persons/pilots, but we'll recreate them to be sure

# 1. Create Companies
co1, _ = Company.objects.get_or_create(
    full_name="SkyHigh Services",
    defaults={"country": "US", "email": "contact@skyhigh.test"}
)
co2, _ = Company.objects.get_or_create(
    full_name="AgriDrones Inc",
    defaults={"country": "US", "email": "ops@agridrones.test"}
)

# 2. Create Persons (Pilots)
# We need to ensure they exist and are linked to the company
p1, _ = Person.objects.get_or_create(
    first_name="John",
    last_name="Skywalker",
    defaults={"email": "john@skyhigh.test"}
)
# Force update company linkage
p1.company = co1
p1.save()

p2, _ = Person.objects.get_or_create(
    first_name="Sarah",
    last_name="Fields",
    defaults={"email": "sarah@agridrones.test"}
)
# Force update company linkage
p2.company = co2
p2.save()

# 3. Create Orphaned Flight Plans
# We create them with operator=None
start_time = datetime.now() + timedelta(days=1)
end_time = start_time + timedelta(hours=2)

targets = [
    {"callsign": "MIG-ERR-101", "pilot": p1}, # Should be SkyHigh
    {"callsign": "MIG-ERR-102", "pilot": p2}, # Should be AgriDrones
    {"callsign": "MIG-ERR-103", "pilot": p1}, # Should be SkyHigh
]

for t in targets:
    fp, created = FlightPlan.objects.get_or_create(
        callsign=t["callsign"],
        defaults={
            "name": f"Migration Error Recovery {t['callsign']}",
            "start_time": start_time,
            "end_time": end_time,
            "pilot": t["pilot"],
            # operator is explicitly NOT set here
        }
    )
    # Force operator to None (NULL) to simulate orphan status
    # This might require bypassing validation if the model enforces it, 
    # but usually 'blank=True, null=True' is allowed in Aerobridge for draft plans
    fp.operator = None
    fp.pilot = t["pilot"]
    fp.save()
    print(f"Created orphan plan: {fp.callsign} (Pilot: {fp.pilot}, Operator: {fp.operator})")

print("Scenario data setup complete.")
PYEOF

# 3. Record start time for anti-gaming
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

# 4. Prepare Browser
echo "Launching Firefox to admin panel..."
pkill -9 -f firefox 2>/dev/null || true
sleep 1

# Clean profile locks
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock

# Launch Firefox
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/gcs_operations/flightplan/' &"

# Wait for window and maximize
sleep 5
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Capture Initial Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="