#!/bin/bash
# setup_task.sh - Pre-task hook for batch_cancel_missed_flights
# Injects specific FlightPlan scenarios:
# 1. Past & Planned (Should be Cancelled)
# 2. Past & Completed (Should be ignored)
# 3. Future & Planned (Should be ignored)

set -e
echo "=== Setting up Batch Cancel Missed Flights Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Aerobridge to be ready
wait_for_aerobridge 60 || echo "WARNING: Aerobridge server may not be ready"

# Record start time
date +%s > /tmp/task_start_time.txt

# Inject Test Data using Python/Django shell
echo "Injecting scenario data..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os
import sys
import django
import json
from datetime import timedelta
from django.utils import timezone

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

try:
    # Import likely models - adapting to potential schema variations
    from gcs_operations.models import FlightPlan
    from registry.models import Aircraft, Pilot
    
    # Get dependencies
    aircraft = Aircraft.objects.first()
    if not aircraft:
        print("Creating dummy aircraft...")
        aircraft = Aircraft.objects.create(name="TestDrone", status=1)
        
    # Define times
    now = timezone.now()
    past_2days = now - timedelta(days=2)
    past_1hour = now - timedelta(hours=1)
    future_1day = now + timedelta(days=1)
    
    # Status constants (assuming standard: 1=Planned, 3=Completed, 4=Cancelled - will verify in script)
    # We will look up choices if possible, otherwise use integer assumptions or strings if model uses strings
    # Inspecting choices programmatically is safer
    
    STATUS_PLANNED = 1
    STATUS_COMPLETED = 3
    STATUS_CANCELLED = 4
    
    # Clean up any existing test data from previous runs to ensure clean slate
    FlightPlan.objects.filter(name__startswith="TASK_TEST_").delete()
    
    ids = {}
    
    # 1. GHOST FLIGHT (The target) - Past and Planned
    f1 = FlightPlan.objects.create(
        name="TASK_TEST_GHOST_1",
        start_datetime=past_2days,
        end_datetime=past_2days + timedelta(hours=1),
        status=STATUS_PLANNED,
        aircraft=aircraft
    )
    ids['ghost_1'] = str(f1.pk)
    print(f"Created GHOST_1 (Should be Cancelled): {f1.pk}")

    # 2. JUST MISSED (Target) - Recently passed and Planned
    f2 = FlightPlan.objects.create(
        name="TASK_TEST_GHOST_RECENT",
        start_datetime=past_1hour - timedelta(hours=1),
        end_datetime=past_1hour,
        status=STATUS_PLANNED,
        aircraft=aircraft
    )
    ids['ghost_recent'] = str(f2.pk)
    print(f"Created GHOST_RECENT (Should be Cancelled): {f2.pk}")

    # 3. HISTORY PRESERVED - Past and Completed
    f3 = FlightPlan.objects.create(
        name="TASK_TEST_COMPLETED",
        start_datetime=past_2days,
        end_datetime=past_2days + timedelta(hours=1),
        status=STATUS_COMPLETED,
        aircraft=aircraft
    )
    ids['completed'] = str(f3.pk)
    print(f"Created COMPLETED (Should NOT change): {f3.pk}")

    # 4. FUTURE PRESERVED - Future and Planned
    f4 = FlightPlan.objects.create(
        name="TASK_TEST_FUTURE",
        start_datetime=future_1day,
        end_datetime=future_1day + timedelta(hours=1),
        status=STATUS_PLANNED,
        aircraft=aircraft
    )
    ids['future'] = str(f4.pk)
    print(f"Created FUTURE (Should NOT change): {f4.pk}")

    # Save IDs to tmp file for export script
    with open('/tmp/test_flight_ids.json', 'w') as f:
        json.dump(ids, f)

except Exception as e:
    print(f"Error injecting data: {e}")
    # Create a fallback JSON so export doesn't crash completely
    with open('/tmp/test_flight_ids.json', 'w') as f:
        json.dump({"error": str(e)}, f)

PYEOF

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Launch VS Code or Terminal to hint at the task location
echo "Launching Terminal..."
su - ga -c "DISPLAY=:1 x-terminal-emulator &"
sleep 2

# Maximize
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="