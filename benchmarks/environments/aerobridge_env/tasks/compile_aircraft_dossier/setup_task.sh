#!/bin/bash
set -e

echo "=== Setting up compile_aircraft_dossier task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure server is running
wait_for_aerobridge 60

# Remove any pre-existing report file
rm -f /home/ga/aircraft_dossier.txt
rm -f /home/ga/dossier_assignment.txt

# Query the database to pick a target aircraft and store ground truth
echo "Querying database for target aircraft..."

# We execute python code within the Aerobridge environment to pick a random aircraft
# and extract its ground truth data directly from the models.
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os
import sys
import django
import json
import random

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Aircraft

# Helper to safely get string values
def safe_str(obj, attr, default='N/A'):
    if not obj:
        return default
    val = getattr(obj, attr, None)
    return str(val) if val else default

# Get aircraft that have at least some data to make it interesting
# Prefer ones with a manufacturer
aircraft_qs = Aircraft.objects.select_related('manufacturer', 'type_certificate', 'operator').all()
candidates = [a for a in aircraft_qs if a.manufacturer]

if not candidates:
    # Fallback to any aircraft
    candidates = list(aircraft_qs)

if not candidates:
    print('ERROR: No aircraft in database')
    sys.exit(1)

# Pick a random target
target = random.choice(candidates)

# Gather Ground Truth
gt = {
    "aircraft_id": str(target.id),
    # Try different field names since models might vary slightly in versions
    "aircraft_model": safe_str(target, 'model', safe_str(target, 'name', 'Unknown')),
    "mass": safe_str(target, 'mass', safe_str(target, 'max_certified_takeoff_weight', 'N/A')),
    "icao_designator": safe_str(target, 'icao_aircraft_type_designator', safe_str(target, 'type_designator', 'N/A')),
    "registration_mark": safe_str(target, 'registration_mark', 'N/A'),
    "sub_category": safe_str(target, 'sub_category', 'N/A'),
    "status": safe_str(target, 'status', 'N/A'),
}

# Manufacturer Details
if target.manufacturer:
    gt["manufacturer_name"] = safe_str(target.manufacturer, 'full_name', str(target.manufacturer))
    gt["manufacturer_country"] = safe_str(target.manufacturer, 'country', 'N/A')
else:
    gt["manufacturer_name"] = "N/A"
    gt["manufacturer_country"] = "N/A"

# Type Certificate Details
if target.type_certificate:
    gt["type_certificate_id"] = str(target.type_certificate.id) # ID often used as identifier
else:
    gt["type_certificate_id"] = "N/A"

# Operator Details
if target.operator:
    gt["operator_name"] = safe_str(target.operator, 'company_name', safe_str(target.operator, 'full_name', str(target.operator)))
    gt["operator_country"] = safe_str(target.operator, 'country', 'N/A')
else:
    gt["operator_name"] = "N/A"
    gt["operator_country"] = "N/A"

# Write Ground Truth (Hidden)
with open('/tmp/aircraft_ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)

# Write Assignment File (Visible)
assignment_text = f"""AIRCRAFT DOSSIER ASSIGNMENT
========================================

Target Aircraft Identifier: {gt['aircraft_model']}
Registration Mark: {gt['registration_mark']}
System ID: {gt['aircraft_id']}

INSTRUCTIONS:
1. Log in to Aerobridge Admin (admin/adminpass123)
2. Locate this aircraft in the Registry
3. Compile a full dossier report in /home/ga/aircraft_dossier.txt
4. Include details for the aircraft, manufacturer, type certificate, and operator.
"""

with open('/home/ga/dossier_assignment.txt', 'w') as f:
    f.write(assignment_text)

print(f"Selected target: {gt['aircraft_model']} (ID: {gt['aircraft_id']})")
PYEOF

# Set permissions
chown ga:ga /home/ga/dossier_assignment.txt
chmod 600 /tmp/aircraft_ground_truth.json

# Launch Firefox to admin panel
launch_firefox "http://localhost:8000/admin/login/"

# Wait for Firefox to load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="