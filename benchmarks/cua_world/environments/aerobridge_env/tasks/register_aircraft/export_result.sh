#!/bin/bash
# export_result.sh — post_task hook for register_aircraft
# Aircraft model uses 'name' field (confirmed from actual DB inspection)
# Registry models: Aircraft(name, operator, manufacturer), Company(full_name, country)

echo "=== Exporting register_aircraft result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/register_aircraft_final.png 2>/dev/null || true

# Read task start time and initial count
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")
COUNT_BEFORE=$(cat /tmp/aircraft_count_before 2>/dev/null || echo "0")

# Export result from Aerobridge database using Django ORM
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os, sys, django, json
from datetime import datetime

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

task_start = '${TASK_START}'
count_before = int('${COUNT_BEFORE}' or '0')

result = {
    "task": "register_aircraft",
    "task_start_time": task_start,
    "count_before": count_before,
    "aircraft": None,
    "current_count": 0,
    "error": None
}

try:
    from registry.models import Aircraft

    current_count = Aircraft.objects.count()
    result["current_count"] = current_count

    # Aircraft model has 'name' field (confirmed from actual Aerobridge source inspection)
    # Fields: id, operator, manufacturer, name, flight_controller_id, status, etc.
    aircraft_qs = Aircraft.objects.filter(name='Phoenix Mk3')

    if aircraft_qs.exists():
        ac = aircraft_qs.first()
        result["aircraft"] = {
            "id": str(ac.pk),
            "name": str(ac.name or ''),
            "operator": str(ac.operator) if ac.operator else '',
            "manufacturer": str(ac.manufacturer) if ac.manufacturer else '',
            "created": str(getattr(ac, 'created_at', 'unknown')),
        }
        print(f"Found aircraft: {result['aircraft']['name']}")
    else:
        # Get most recently created aircraft as fallback
        recent = Aircraft.objects.order_by('-created_at').first()
        if recent:
            result["aircraft"] = {
                "id": str(recent.pk),
                "name": str(recent.name or ''),
                "note": "most_recent_fallback"
            }
        print("Aircraft 'Phoenix Mk3' not found in registry. Count:", current_count, "Before:", count_before)

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")

# Write result to file
result_path = '/tmp/register_aircraft_result.json'
with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)
print(f"Result written to {result_path}")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
