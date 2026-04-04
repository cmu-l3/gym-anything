#!/bin/bash
# export_result.sh — post_task hook for identify_inactive_operators
# Calculates ground truth from DB and compares with agent output inside the container.

echo "=== Exporting identify_inactive_operators result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Run Python analysis to generate result JSON
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os
import sys
import json
import django
from datetime import timedelta
from django.utils import timezone

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Company
from flight_plans.models import FlightPlan

REPORT_PATH = "/home/ga/Documents/inactive_operators_report.txt"
THRESHOLD_DAYS = 90

result = {
    "report_exists": False,
    "report_content": [],
    "ground_truth_inactive": [],
    "ground_truth_active": [],
    "correct_matches": [],
    "false_positives": [], # Active companies incorrectly listed
    "false_negatives": [], # Inactive companies missed
    "score_metrics": {},
    "timestamp": str(timezone.now())
}

# --- 1. Calculate Ground Truth ---
threshold_date = timezone.now() - timedelta(days=THRESHOLD_DAYS)
all_companies = Company.objects.all()

for comp in all_companies:
    # Get latest flight plan
    last_flight = FlightPlan.objects.filter(company=comp).order_by('-start_time').first()
    
    is_inactive = False
    if last_flight is None:
        is_inactive = True
    elif last_flight.start_time < threshold_date:
        is_inactive = True
        
    if is_inactive:
        result["ground_truth_inactive"].append(comp.name)
    else:
        result["ground_truth_active"].append(comp.name)

# --- 2. Read Agent Report ---
if os.path.exists(REPORT_PATH):
    result["report_exists"] = True
    try:
        with open(REPORT_PATH, 'r') as f:
            # Read lines, strip whitespace, ignore empty lines
            lines = [line.strip() for line in f.readlines() if line.strip()]
            result["report_content"] = lines
    except Exception as e:
        result["error"] = str(e)

# --- 3. Compare ---
if result["report_exists"]:
    agent_set = set(result["report_content"])
    inactive_set = set(result["ground_truth_inactive"])
    active_set = set(result["ground_truth_active"])
    
    # False Positives: Agent listed an ACTIVE company (Bad!)
    # We do a case-insensitive check to be lenient on capitalization, 
    # but strict on the name itself.
    active_lower = {n.lower(): n for n in active_set}
    inactive_lower = {n.lower(): n for n in inactive_set}
    
    for name in agent_set:
        name_lower = name.lower()
        if name_lower in active_lower:
            result["false_positives"].append(active_lower[name_lower])
        elif name_lower in inactive_lower:
            result["correct_matches"].append(inactive_lower[name_lower])
        else:
            # Name doesn't exist in DB at all (Hallucination)
            # We treat hallucinated names as minor errors or ignore them depending on strictness.
            # For now, let's flag them.
            pass

    # False Negatives: Agent missed an INACTIVE company
    # Check which actual inactive ones were NOT found
    agent_lower = {n.lower() for n in agent_set}
    for name in inactive_set:
        if name.lower() not in agent_lower:
            result["false_negatives"].append(name)

# --- 4. Save Result ---
result_file = '/tmp/task_result.json'
with open(result_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Result exported to {result_file}")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="