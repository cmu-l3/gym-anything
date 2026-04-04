#!/bin/bash
# setup_task.sh - Prepares data for bulk_dispatch_assignment
# 1. Creates Pilots (Persons + Pilot records)
# 2. Creates Flight Plans (unassigned)
# 3. Generates CSV roster
# 4. Saves ground truth for verification

echo "=== Setting up Bulk Dispatch Assignment Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Aerobridge to be responsive
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Directory setup
mkdir -p /home/ga/Documents
mkdir -p /var/lib/aerobridge

# Python script to generate data and CSV
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os
import sys
import django
import csv
import json
import random
from datetime import datetime

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Person, Pilot, Aircraft
from gcs_operations.models import FlightPlan

print("Generating scenario data...")

# 1. Clear relevant data to ensure clean state
# Note: In a real env we might not want to delete everything, but for this task 
# we need specific IDs to match the CSV. We'll create new records.

# 2. Create Pilots (Person + Pilot)
pilot_data = [
    ("Amit", "Singh", "amit.s@droneops.io"),
    ("Sarah", "Jenkins", "sarah.j@droneops.io"),
    ("David", "Chen", "david.c@droneops.io"),
    ("Priya", "Patel", "priya.p@droneops.io"),
    ("Michael", "Ross", "mike.r@droneops.io")
]

created_pilots = {} # email -> pilot_obj

for first, last, email in pilot_data:
    # Create or get Person
    p, _ = Person.objects.get_or_create(
        email=email,
        defaults={'first_name': first, 'last_name': last}
    )
    # Create or get Pilot linked to Person
    pilot, _ = Pilot.objects.get_or_create(person=p)
    created_pilots[email] = pilot
    print(f"Ensured Pilot: {first} {last} ({email})")

# 3. Create Flight Plans (Unassigned)
# We need enough plans to assign, plus some extras/decoys
plans = []
for i in range(1, 11):
    name = f"Survey Mission Block {i}"
    # Create dummy FP
    fp = FlightPlan.objects.create(
        name=name,
        start_time=datetime.now(),
        end_time=datetime.now(),
        # Ensure pilot is None initially
        pilot=None 
    )
    plans.append(fp)
    print(f"Created FlightPlan: {fp.id} - {fp.name}")

# 4. Generate Roster (CSV)
# Map first 5 plans to the 5 pilots
roster = []
ground_truth = {}

for i, (email, pilot_obj) in enumerate(created_pilots.items()):
    fp = plans[i]
    roster.append([fp.id, email])
    # Store ID and Email for verification
    ground_truth[str(fp.id)] = {
        "expected_email": email,
        "expected_pilot_id": pilot_obj.id,
        "expected_person_id": pilot_obj.person.id
    }

# Add a "trap" row - non-existent email to test robustness (optional, strictly speaking standard agents might fail, so we'll keep it simple for now and stick to valid data to ensure solvability, or add one valid but unassigned plan)
# Let's just stick to valid assignments for this version.

csv_path = "/home/ga/Documents/pilot_roster.csv"
with open(csv_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["flight_plan_id", "pilot_email"]) # Header
    writer.writerows(roster)

print(f"Generated roster CSV at {csv_path}")

# 5. Save Ground Truth (Hidden)
gt_path = "/var/lib/aerobridge/roster_ground_truth.json"
with open(gt_path, 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Saved ground truth to {gt_path}")

PYEOF

# Fix permissions
chown ga:ga /home/ga/Documents/pilot_roster.csv
chmod 644 /home/ga/Documents/pilot_roster.csv

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Firefox for the agent to inspect models via Admin if they choose
echo "Launching Firefox..."
pkill -9 -f firefox 2>/dev/null || true
su - ga -c "DISPLAY=:1 setsid firefox 'http://localhost:8000/admin/' &"
sleep 5

# Screenshot initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="