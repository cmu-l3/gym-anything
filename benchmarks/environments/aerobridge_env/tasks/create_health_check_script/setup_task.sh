#!/bin/bash
# setup_task.sh - Pre-task setup for create_health_check_script

echo "=== Setting up Health Check Script Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Ensure Aerobridge server is running (critical for the agent to check it)
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Clean up any previous run artifacts
rm -f /opt/aerobridge/health_check.sh
rm -f /opt/aerobridge/health_report.json

# 3. Record task start time for anti-gaming verification
# Using ISO format for easier comparison in Python, and epoch for shell
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_iso.txt
date +%s > /tmp/task_start_time.txt

# 4. Record initial DB state (Ground Truth for setup)
# We calculate this now just to log it, but will recalculate in export_result
# to verify against the agent's fresh run.
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 -c "
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()
from registry.models import Aircraft
print(f'Setup Check - Aircraft count: {Aircraft.objects.count()}')
" || echo "Setup DB check failed"

# 5. Open terminal or editor?
# We'll just open the browser to the admin panel so the agent can see the app is alive.
# The agent will likely use the terminal to write the script.
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/"

# 6. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="