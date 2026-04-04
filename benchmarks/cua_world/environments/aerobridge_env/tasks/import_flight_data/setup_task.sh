#!/bin/bash
set -e

echo "=== Setting up Import Flight Data Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Ensure Aerobridge server is ready
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Generate Mission Specs Data File
# We explicitly provide Lat, Lon to test the agent's ability to swap to Lon, Lat for GeoJSON
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/mission_specs.txt << 'EOF'
MISSION PARAMETERS
==================
Mission ID: HAWK-EYE-2024
Target: Draft Survey Mission

SCHEDULE (UTC):
Start Time: 2025-11-15 08:30:00
End Time:   2025-11-15 12:45:00

BOUNDARY COORDINATES (Latitude, Longitude):
38.9000, -95.1000
38.9000, -95.0900
38.9100, -95.0900
38.9100, -95.1000
EOF

chown ga:ga /home/ga/Documents/mission_specs.txt
chmod 644 /home/ga/Documents/mission_specs.txt

# 3. Create the Placeholder Flight Plan via Django ORM
# We delete any existing one first to ensure a clean state
echo "Creating placeholder flight plan..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, json
from django.utils import timezone
from datetime import datetime

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import FlightPlan, Person

# Get or create a pilot
pilot, _ = Person.objects.get_or_create(
    first_name='Test', last_name='Pilot',
    defaults={'email': 'pilot@test.com'}
)

# Clean up existing
FlightPlan.objects.filter(name='Draft Survey Mission').delete()

# Create the draft plan with incorrect times and empty geometry
fp = FlightPlan.objects.create(
    name='Draft Survey Mission',
    description='Placeholder plan awaiting final mission specs.',
    start_time=timezone.now(),
    end_time=timezone.now(),
    pilot=pilot,
    geometry=None # Empty geometry
)
print(f"Created FlightPlan: {fp.name} (ID: {fp.id})")
PYEOF

# 4. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 5. Launch Firefox directly to the Flight Plan admin page
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/registry/flightplan/"

# 6. Capture initial state screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="