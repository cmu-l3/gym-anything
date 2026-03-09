#!/bin/bash
# setup_task.sh - Pre-task setup for calculate_operational_bounds
set -e

echo "=== Setting up calculate_operational_bounds task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Aerobridge server is ready (DB must be accessible)
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 3. Clean up any previous attempts
rm -f /home/ga/operational_bounds.json
rm -f /home/ga/calc_bounds.py
rm -f /tmp/task_result.json

# 4. Inject specific test data to ensure the task is deterministic and non-trivial
# We add a flight plan with known extreme coordinates to ensure the bounding box isn't just (0,0,0,0)
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, json
from datetime import datetime, timedelta

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

try:
    # Try importing FlightPlan (location varies by version)
    try:
        from gcs_operations.models import FlightPlan
    except ImportError:
        from gcs_operations.models import GCSFlightPlan as FlightPlan
    
    # Create a dummy flight plan with known bounds if DB is empty or for robustness
    # Extremes: Min Lat 10.0, Max Lat 20.0, Min Lon 70.0, Max Lon 80.0
    
    # Check if we need to inject data
    if FlightPlan.objects.count() < 3:
        print("Injecting sample flight plans for task...")
        
        # Plan 1: The "South-West" extreme
        geo_sw = {
            "type": "LineString",
            "coordinates": [
                [70.00000, 10.00000],  # Min Lon, Min Lat
                [70.50000, 10.50000]
            ]
        }
        FlightPlan.objects.create(
            name="Task_SW_Limit",
            start_datetime=datetime.now(),
            end_datetime=datetime.now() + timedelta(hours=1),
            geometry=json.dumps(geo_sw)
        )
        
        # Plan 2: The "North-East" extreme
        geo_ne = {
            "type": "Polygon",
            "coordinates": [[
                [80.00000, 20.00000],  # Max Lon, Max Lat
                [79.50000, 19.50000],
                [80.00000, 20.00000]
            ]]
        }
        FlightPlan.objects.create(
            name="Task_NE_Limit",
            start_datetime=datetime.now(),
            end_datetime=datetime.now() + timedelta(hours=1),
            geometry=json.dumps(geo_ne)
        )
        print("Injected extreme flight plans.")
    else:
        print(f"Database already has {FlightPlan.objects.count()} flight plans. Using existing data.")

except Exception as e:
    print(f"Setup warning: {e}")
PYEOF

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="