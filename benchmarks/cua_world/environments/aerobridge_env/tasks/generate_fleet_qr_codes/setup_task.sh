#!/bin/bash
set -e
echo "=== Setting up Generate Fleet QR Codes task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Aerobridge server is running
ensure_server_running

# Record initial aircraft count to know how many files to expect
echo "Counting aircraft in database..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

AIRCRAFT_COUNT=$(/opt/aerobridge_venv/bin/python3 -c "
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
# Load env vars manually if needed, but source .env above handles it mostly
django.setup()
from registry.models import Aircraft
print(Aircraft.objects.count())
" 2>/dev/null || echo "0")

echo "$AIRCRAFT_COUNT" > /tmp/expected_aircraft_count.txt
echo "System has $AIRCRAFT_COUNT aircraft."

# Ensure the output directory does NOT exist (clean slate)
rm -rf /home/ga/Documents/fleet_tags

# Launch Firefox to the aircraft list to give a visual cue and help agent find URL structure
launch_firefox "http://localhost:8000/admin/registry/aircraft/"

# Maximize Firefox
sleep 5
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="