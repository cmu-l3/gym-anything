#!/bin/bash
# export_result.sh - Post-task hook
# Checks the status of the specific IDs we created and looks for the log file

echo "=== Exporting Results ==="

# 1. Check for Log File
LOG_FILE="/home/ga/Documents/cancelled_flights.log"
LOG_EXISTS="false"
LOG_CONTENT=""

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    LOG_CONTENT=$(cat "$LOG_FILE" | head -n 20) # Read first 20 lines
fi

# 2. Check for Script
SCRIPT_FILE="/home/ga/Documents/cancel_missed_flights.py"
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
fi

# 3. Query Database for Test Records
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os
import sys
import django
import json

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

result = {
    "log_exists": "$LOG_EXISTS" == "true",
    "log_content": """$LOG_CONTENT""",
    "script_exists": "$SCRIPT_EXISTS" == "true",
    "records": {}
}

try:
    # Load the IDs we tracked
    if os.path.exists('/tmp/test_flight_ids.json'):
        with open('/tmp/test_flight_ids.json', 'r') as f:
            ids = json.load(f)
            
        from gcs_operations.models import FlightPlan
        
        # Check each record
        for key, pk in ids.items():
            if key == "error": continue
            
            try:
                fp = FlightPlan.objects.get(pk=pk)
                result['records'][key] = {
                    "id": str(pk),
                    "status": fp.status,
                    "status_display": fp.get_status_display() if hasattr(fp, 'get_status_display') else str(fp.status),
                    "name": fp.name
                }
            except FlightPlan.DoesNotExist:
                result['records'][key] = "MISSING"

except Exception as e:
    result["error"] = str(e)

# Write result
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Add screenshot path to result
jq '.screenshot_path = "/tmp/task_final.png"' /tmp/task_result.json > /tmp/task_result.json.tmp && mv /tmp/task_result.json.tmp /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json