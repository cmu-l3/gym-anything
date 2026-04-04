#!/bin/bash
# setup_task.sh — pre_task hook for add_flight_authorization

echo "=== Setting up add_flight_authorization task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Aerobridge to be ready
wait_for_aerobridge 60 || echo "WARNING: Aerobridge server may not be ready"

# 2. Cleanup: Remove any existing Authorization with the specific title
#    to ensure a clean state for testing.
echo "Cleaning up any previous test records..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
# Load env vars manually if needed
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

try:
    from registry.models import Authorization
    # Delete any existing records with the target title
    count, _ = Authorization.objects.filter(title__icontains='Mumbai Port Area BVLOS').delete()
    if count > 0:
        print(f"Cleaned up {count} existing authorization record(s).")
    else:
        print("No existing records found (clean start).")
except Exception as e:
    print(f"Cleanup warning: {e}")
PYEOF

# 3. Record baseline state (count of authorizations)
#    This is crucial for detecting if a new record was actually created.
AUTH_COUNT_BEFORE=$(/opt/aerobridge_venv/bin/python3 -c "
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip(\"'\").strip('\"'))
django.setup()
from registry.models import Authorization
print(Authorization.objects.count())
" 2>/dev/null || echo "0")

echo "$AUTH_COUNT_BEFORE" > /tmp/auth_count_before
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

echo "Baseline Authorization count: $AUTH_COUNT_BEFORE"
echo "Task start time recorded."

# 4. Launch Firefox to the Admin panel root
#    We start at the root so the agent has to navigate.
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="