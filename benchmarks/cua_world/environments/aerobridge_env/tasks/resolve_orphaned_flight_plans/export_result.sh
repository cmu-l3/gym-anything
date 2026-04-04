#!/bin/bash
echo "=== Exporting resolve_orphaned_flight_plans result ==="

# Record end time
TASK_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "2000-01-01T00:00:00Z")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to query DB and export results
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os
import sys
import django
import json
from datetime import datetime

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

try:
    from gcs_operations.models import FlightPlan
except ImportError:
    try:
        from flight_plans.models import FlightPlan
    except ImportError:
        print("Error: FlightPlan model not found")
        sys.exit(1)

targets = ["MIG-ERR-101", "MIG-ERR-102", "MIG-ERR-103"]
results = {
    "task_start": os.environ.get('TASK_START_TIME', ''),
    "flight_plans": {}
}

print("Querying flight plans...")

for callsign in targets:
    try:
        fp = FlightPlan.objects.get(callsign=callsign)
        
        # Get operator name safely
        op_name = None
        if fp.operator:
            # Check likely name fields
            op_name = getattr(fp.operator, 'full_name', 
                     getattr(fp.operator, 'name', 
                     getattr(fp.operator, 'company_name', 'Unknown')))
        
        # Get updated_at timestamp safely
        updated_at = None
        if hasattr(fp, 'updated_at') and fp.updated_at:
            updated_at = fp.updated_at.isoformat()
        
        results["flight_plans"][callsign] = {
            "exists": True,
            "operator": op_name,
            "updated_at": updated_at
        }
    except FlightPlan.DoesNotExist:
        results["flight_plans"][callsign] = {
            "exists": False,
            "operator": None,
            "error": "Not Found"
        }

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)

print("Export complete.")
PYEOF

# Adjust permissions so agent/verifier can read it
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="