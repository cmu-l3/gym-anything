#!/bin/bash
set -e
echo "=== Setting up Task: Create Cleanup Command ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Aerobridge server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Inject Canary Data
# We need:
# - Plan A: Expired & Active (Should change to Closed)
# - Plan B: Future & Active (Should remain Active)
# - Plan C: Expired & Closed (Should remain Closed)

echo "Injecting canary flight plans..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
import json
from datetime import timedelta
from django.utils import timezone

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

try:
    # Handle potential model location changes
    try:
        from registry.models import FlightPlan
    except ImportError:
        from gcs_operations.models import FlightPlan
    
    from registry.models import Aircraft, Person, Company
    
    # Ensure dependencies exist
    aircraft = Aircraft.objects.first()
    if not aircraft:
        print("Creating dummy aircraft...")
        op = Company.objects.create(full_name="Test Op", country="US")
        aircraft = Aircraft.objects.create(name="TestDrone", operator=op, status="Active")
        
    pilot = Person.objects.first()
    if not pilot:
        pilot = Person.objects.create(first_name="Test", last_name="Pilot", email="test@example.com")

    now = timezone.now()

    # Create Canary 1: Expired Active
    c1 = FlightPlan.objects.create(
        name="CANARY_EXPIRED_ACTIVE",
        start_time=now - timedelta(hours=5),
        end_time=now - timedelta(hours=2),
        status="Active",
        aircraft=aircraft,
        pilot=pilot
    )

    # Create Canary 2: Future Active
    c2 = FlightPlan.objects.create(
        name="CANARY_FUTURE_ACTIVE",
        start_time=now + timedelta(hours=1),
        end_time=now + timedelta(hours=5),
        status="Active",
        aircraft=aircraft,
        pilot=pilot
    )

    # Create Canary 3: Expired Closed
    c3 = FlightPlan.objects.create(
        name="CANARY_EXPIRED_CLOSED",
        start_time=now - timedelta(hours=10),
        end_time=now - timedelta(hours=8),
        status="Closed",
        aircraft=aircraft,
        pilot=pilot
    )

    canaries = {
        "expired_active_id": c1.id,
        "future_active_id": c2.id,
        "expired_closed_id": c3.id
    }

    with open('/tmp/canaries.json', 'w') as f:
        json.dump(canaries, f)
        
    print(f"Canaries created: {canaries}")

except Exception as e:
    print(f"Error injecting data: {e}")
    sys.exit(1)
PYEOF

# 4. Open a terminal for the agent (since this is a coding task)
if [ -x /usr/bin/gnome-terminal ]; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
elif [ -x /usr/bin/x-terminal-emulator ]; then
    su - ga -c "DISPLAY=:1 x-terminal-emulator &"
fi

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="