#!/bin/bash
# setup_task.sh — pre_task hook for identify_inactive_operators
# Generates a mix of active and inactive companies with specific flight history dates.

echo "=== Setting up identify_inactive_operators task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

# Wait for server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Generate Dynamic Data using Python
echo "Generating fleet activity data..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os
import sys
import django
import random
from datetime import datetime, timedelta
from django.utils import timezone

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Company
from flight_plans.models import FlightPlan
from django.contrib.auth.models import User

# Create a pilot user for the flight plans
u, _ = User.objects.get_or_create(username='sim_pilot_auto')

def create_scenario(name_prefix, days_ago_list):
    """
    Creates a company and a set of flight plans for it.
    days_ago_list: list of integers representing how many days ago a flight occurred.
                   Empty list means no flights.
    """
    suffix = str(random.randint(1000, 9999))
    name = f"{name_prefix}_{suffix}"
    
    # Create Company
    company, _ = Company.objects.get_or_create(name=name, defaults={'acronym': name[:3].upper()})
    
    # Create Flight Plans
    now = timezone.now()
    for days in days_ago_list:
        start = now - timedelta(days=days)
        end = start + timedelta(hours=1)
        
        FlightPlan.objects.create(
            name=f"Flight {name} - {days} days ago",
            company=company,
            start_time=start,
            end_time=end,
            min_altitude=10,
            max_altitude=50,
            submitted_by=u
        )
    return name

# --- SCENARIO GENERATION ---

# 1. Active: Flight 5 days ago
n1 = create_scenario("ActiveLogistics", [5, 20, 100])
print(f"Created ACTIVE operator: {n1} (Last flight 5 days ago)")

# 2. Active Boundary: Flight 89 days ago (Just inside 90 day window)
n2 = create_scenario("BorderlineActive", [89, 200])
print(f"Created ACTIVE operator: {n2} (Last flight 89 days ago)")

# 3. Inactive Boundary: Flight 91 days ago (Just outside 90 day window)
n3 = create_scenario("JustInactive", [91, 150])
print(f"Created INACTIVE operator: {n3} (Last flight 91 days ago)")

# 4. Inactive: Flight 300 days ago
n4 = create_scenario("AncientDrones", [300, 400])
print(f"Created INACTIVE operator: {n4} (Last flight 300 days ago)")

# 5. Inactive: No flights ever
n5 = create_scenario("GhostFlyers", [])
print(f"Created INACTIVE operator: {n5} (No flights)")

# Clean up older test runs if needed (optional, kept simple for now)
print("Data generation complete.")
PYEOF

# Launch Firefox to admin panel
echo "Launching Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Reset profile locks
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock

su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/' > /dev/null 2>&1 &"

# Capture initial state
sleep 8
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="