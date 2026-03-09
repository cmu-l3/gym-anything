#!/bin/bash
# setup_task.sh — pre_task hook for register_oauth_application

echo "=== Setting up register_oauth_application task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Aerobridge server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Clean previous task artifacts
echo "Cleaning up previous state..."
rm -f /home/ga/Documents/skylinks_creds.txt

# 3. Clean database state: Remove any existing app named "SkyLinks GCS"
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

try:
    from oauth2_provider.models import Application
    count, _ = Application.objects.filter(name='SkyLinks GCS').delete()
    print(f"Removed {count} existing 'SkyLinks GCS' application(s)")
except Exception as e:
    print(f"Cleanup warning: {e}")
PYEOF

# 4. Record start time
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

# 5. Launch Firefox to Admin Panel
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/"

# 6. Capture initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="