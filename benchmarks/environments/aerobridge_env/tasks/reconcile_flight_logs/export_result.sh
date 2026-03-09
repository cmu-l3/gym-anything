#!/bin/bash
echo "=== Exporting Reconcile Flight Logs Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if report file exists
REPORT_FILE="/home/ga/Documents/unmatched_logs.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE")
fi

# Query current state of the logs using the IDs saved during setup
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os, sys, django, json

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from gcs_operations.models import FlightLog

# Load the IDs we tracked
try:
    with open('/tmp/recon_ids.json', 'r') as f:
        ids = json.load(f)
except FileNotFoundError:
    print("Error: Setup IDs not found")
    sys.exit(1)

# Helper to get plan ID safely
def get_plan_id(log_id):
    try:
        log = FlightLog.objects.get(id=log_id)
        return log.flight_plan.id if log.flight_plan else None
    except FlightLog.DoesNotExist:
        return "MISSING"

current_state = {
    "ids": ids,
    "log_1_actual_plan": get_plan_id(ids['log_1_id']),  # Should be plan_1_id
    "log_2_actual_plan": get_plan_id(ids['log_2_id']),  # Should be plan_2_id
    "log_3_actual_plan": get_plan_id(ids['log_3_id']),  # Should be None
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_content": """$REPORT_CONTENT"""
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(current_state, f, indent=2)

print("Exported state:")
print(json.dumps(current_state, indent=2))
PYEOF

# Ensure permissions for verify
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="