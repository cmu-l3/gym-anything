#!/bin/bash
# export_result.sh — post_task hook for create_flight_plan

echo "=== Exporting create_flight_plan result ==="

DISPLAY=:1 scrot /tmp/create_flight_plan_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")
COUNT_BEFORE=$(cat /tmp/flightplan_count_before 2>/dev/null || echo "0")

cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os, sys, django, json

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
    "task": "create_flight_plan",
    "task_start_time": task_start,
    "count_before": count_before,
    "flight_plan": None,
    "current_count": 0,
    "error": None
}

try:
    from gcs_operations.models import FlightPlan

    current_count = FlightPlan.objects.count()
    result["current_count"] = current_count

    # Try to find by name field variations
    fp = None
    for name_field in ['name', 'flight_plan_name', 'plan_name']:
        try:
            fp = FlightPlan.objects.filter(**{name_field: 'Mumbai Coastal Survey'}).first()
            if fp:
                break
        except Exception:
            pass

    if fp:
        result["flight_plan"] = {
            "id": fp.pk,
            "name": str(getattr(fp, 'name', getattr(fp, 'flight_plan_name', 'unknown')) or ''),
        }
        # Try to get description
        for desc_field in ['description', 'geo_data_text', 'details', 'notes']:
            val = getattr(fp, desc_field, None)
            if val:
                result["flight_plan"]["description"] = str(val)
                break
        print(f"Found flight plan: {result['flight_plan']['name']}")
    else:
        # Fallback: most recent
        recent = FlightPlan.objects.order_by('-id').first()
        if recent:
            result["flight_plan"] = {
                "id": recent.pk,
                "name": str(
                    getattr(recent, 'name',
                    getattr(recent, 'flight_plan_name', 'unknown')) or ''
                ),
                "note": "most_recent_fallback"
            }
        print("Flight plan 'Mumbai Coastal Survey' not found")

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")

result_path = '/tmp/create_flight_plan_result.json'
with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)
print(f"Result written to {result_path}")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
