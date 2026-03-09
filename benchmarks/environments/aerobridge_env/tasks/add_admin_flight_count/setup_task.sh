#!/bin/bash
# setup_task.sh — pre_task hook for add_admin_flight_count

echo "=== Setting up add_admin_flight_count task ==="

# Source utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for server to be ready
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Record start time
date +%s > /tmp/task_start_time.txt

# 3. Create backup of admin.py for comparison
cp /opt/aerobridge/registry/admin.py /tmp/admin_py_initial

# 4. Inject Test Data: Ensure some aircraft have flight plans
# We need non-zero counts to make the column meaningful
echo "Injecting test flight plans..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
from datetime import timedelta
from django.utils import timezone

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

try:
    from registry.models import Aircraft
    from gcs_operations.models import FlightPlan
    
    # Get the first aircraft
    ac = Aircraft.objects.first()
    if ac:
        print(f"Adding flight plans to aircraft: {ac.name} ({ac.pk})")
        # Create 3 dummy plans
        for i in range(3):
            FlightPlan.objects.create(
                name=f"Task Setup Plan {i}",
                start_time=timezone.now(),
                end_time=timezone.now() + timedelta(hours=1),
                aircraft=ac, # Depending on model, field might be 'aircraft' or 'drone'
                # Minimal required fields usually include geometry, let's try generic
                geometry="POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))"
            )
        print("Flight plans injected successfully.")
    else:
        print("No aircraft found to attach plans to.")

except Exception as e:
    print(f"Data injection warning: {e}")
PYEOF

# 5. Launch Firefox to the Aircraft Admin page
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/registry/aircraft/"

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="