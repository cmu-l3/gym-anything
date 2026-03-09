#!/bin/bash
set -e

echo "=== Exporting Import Flight Data Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Export Data from Django
# We extract the specific flight plan's details to JSON
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os, sys, django, json
from datetime import datetime

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import FlightPlan

result = {
    "found": False,
    "start_time": None,
    "end_time": None,
    "geometry": None,
    "modified_after_start": False,
    "task_start_ts": int("${TASK_START}"),
    "updated_at_ts": 0
}

try:
    fp = FlightPlan.objects.filter(name='Draft Survey Mission').first()
    
    if fp:
        result["found"] = True
        
        # Format datetimes as strings for JSON
        # Django DateTimes are timezone aware (usually UTC)
        if fp.start_time:
            result["start_time"] = fp.start_time.strftime("%Y-%m-%d %H:%M:%S")
        
        if fp.end_time:
            result["end_time"] = fp.end_time.strftime("%Y-%m-%d %H:%M:%S")
            
        # Get Geometry (it's a JSONField, so we get a dict or list)
        result["geometry"] = fp.geometry
        
        # Check modification timestamp if available (most Django models have auto_now=True on updated_at)
        # Assuming FlightPlan has updated_at or similar. If not, we rely on value correctness.
        # Checking standard fields if they exist
        updated_at = getattr(fp, 'updated_at', getattr(fp, 'modified_at', None))
        
        if updated_at:
            result["updated_at_ts"] = updated_at.timestamp()
            if updated_at.timestamp() > int("${TASK_START}"):
                result["modified_after_start"] = True
        else:
            # Fallback: assume modified if values are correct (handled by verifier)
            pass

except Exception as e:
    result["error"] = str(e)

# Write to temp file
with open('/tmp/import_flight_data_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported result to /tmp/import_flight_data_result.json")
PYEOF

# 4. Move result to standard location ensuring permissions
mv /tmp/import_flight_data_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="