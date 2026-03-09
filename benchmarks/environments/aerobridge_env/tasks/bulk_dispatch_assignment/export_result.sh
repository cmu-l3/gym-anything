#!/bin/bash
# export_result.sh - Extracts final FlightPlan assignments for verification

echo "=== Exporting Bulk Dispatch Results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Data using Django
# We need to read the current state of the FlightPlans that were in the ground truth
# and dump them to a JSON file for the verifier.

GT_PATH="/var/lib/aerobridge/roster_ground_truth.json"

if [ ! -f "$GT_PATH" ]; then
    echo "Error: Ground truth file missing. Setup likely failed."
    exit 1
fi

cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os
import sys
import django
import json

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from gcs_operations.models import FlightPlan
from registry.models import Pilot

# Load ground truth to know which IDs to check
with open('/var/lib/aerobridge/roster_ground_truth.json', 'r') as f:
    ground_truth = json.load(f)

results = {}

print("Checking Flight Plan assignments...")

for fp_id, expected in ground_truth.items():
    try:
        fp = FlightPlan.objects.get(pk=fp_id)
        
        # Check assigned pilot
        assigned_pilot = fp.pilot # Assuming field name is 'pilot' based on Aerobridge conventions
        
        if assigned_pilot:
            # Get details to verify against expected
            results[fp_id] = {
                "assigned_pilot_id": assigned_pilot.id,
                "assigned_person_email": assigned_pilot.person.email,
                "status": "assigned"
            }
        else:
            results[fp_id] = {
                "assigned_pilot_id": None,
                "status": "unassigned"
            }
            
    except FlightPlan.DoesNotExist:
        results[fp_id] = {"status": "missing"}
    except Exception as e:
        results[fp_id] = {"status": "error", "message": str(e)}

# Export to /tmp/task_result.json
output = {
    "assignments": results,
    "total_checked": len(results),
    "timestamp": str(os.path.getmtime('/home/ga/Documents/pilot_roster.csv')) # metadata
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)

print("Export complete.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json

cat /tmp/task_result.json
echo "=== Export Complete ==="