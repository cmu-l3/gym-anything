#!/bin/bash
# Export script for generate_fleet_summary
# Gathers the agent's output file AND generates ground truth from DB for verification

echo "=== Exporting generate_fleet_summary result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Basic Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/fleet_summary.txt"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_CONTENT=""

# 2. Check Output File
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read content (base64 encode to safely transport via JSON)
    OUTPUT_CONTENT=$(cat "$OUTPUT_PATH" | base64 -w 0)
fi

# 3. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Generate Ground Truth & Combine with Agent Output
# We run a python script inside the environment to query the DB and produce the final JSON
# This ensures we verify against the ACTUAL current state of the database.

cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os
import sys
import django
import json
import base64

# Setup Django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Company, Aircraft, Person
from gcs_operations.models import FlightPlan

# --- Gather Ground Truth ---
ground_truth = {
    "counts": {
        "operators": Company.objects.count(),
        "aircraft": Aircraft.objects.count(),
        "persons": Person.objects.count(),
        "flight_plans": FlightPlan.objects.count()
    },
    "operators": [],
    "aircraft": [],
    "persons": []
}

# Operators details
for comp in Company.objects.all():
    # Count aircraft for this operator
    ac_count = Aircraft.objects.filter(operator=comp).count()
    ground_truth["operators"].append({
        "name": comp.full_name,
        "country": comp.country,
        "aircraft_count": ac_count
    })

# Aircraft details
for ac in Aircraft.objects.select_related('operator', 'final_assembly').all():
    # Check type certificate
    has_tc = "No"
    if hasattr(ac, 'final_assembly') and ac.final_assembly:
         # Assuming logic: if linked to a type cert model (simplified for verification)
         # We'll just check if the model exists. In reality, we check the text report.
         pass
    
    ground_truth["aircraft"].append({
        "manufacturer": str(ac.manufacturer) if ac.manufacturer else "Unknown",
        "mass": float(ac.mass) if ac.mass else 0,
        "operator": str(ac.operator.full_name) if ac.operator else "None",
        "name": ac.name
    })

# Person details
for p in Person.objects.all():
    # Find associated operator via Pilot model if exists, or generic relation
    # For verification, we just want to see if the agent found the name
    ground_truth["persons"].append({
        "full_name": f"{p.first_name} {p.last_name}"
    })

# --- Prepare Result JSON ---
result_data = {
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_content_b64": "$OUTPUT_CONTENT",
    "ground_truth": ground_truth
}

# Write to temp file
with open('/tmp/temp_result.json', 'w') as f:
    json.dump(result_data, f)
PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
mv /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="