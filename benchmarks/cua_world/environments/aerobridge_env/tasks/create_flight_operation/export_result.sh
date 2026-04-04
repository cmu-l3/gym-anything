#!/bin/bash
# export_result.sh — post_task hook for create_flight_operation

echo "=== Exporting create_flight_operation result ==="

DISPLAY=:1 scrot /tmp/create_flight_operation_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")
COUNT_BEFORE=$(cat /tmp/flightoperation_count_before 2>/dev/null || echo "0")

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
    "task": "create_flight_operation",
    "task_start_time": task_start,
    "count_before": count_before,
    "flight_operation": None,
    "current_count": 0,
    "error": None
}

try:
    from gcs_operations.models import FlightOperation

    current_count = FlightOperation.objects.count()
    result["current_count"] = current_count

    fo = None
    search_term = 'Rajasthan Corridor Inspection'
    for name_field in ['name', 'operation_name', 'description', 'flight_operation_name']:
        try:
            fo = FlightOperation.objects.filter(**{name_field: search_term}).first()
            if fo:
                break
        except Exception:
            pass

    if fo:
        result["flight_operation"] = {
            "id": fo.pk,
            "name": str(
                getattr(fo, 'name',
                getattr(fo, 'operation_name',
                getattr(fo, 'description', 'unknown'))) or ''
            ),
        }
        # Try to get aircraft and pilot info
        for field in ['drone', 'aircraft', 'uav']:
            val = getattr(fo, field, None)
            if val:
                result["flight_operation"]["aircraft"] = str(val)
                break
        print(f"Found flight operation: {result['flight_operation']['name']}")
    else:
        # Fallback: most recent, to check if count changed
        recent = FlightOperation.objects.order_by('-id').first()
        if recent:
            result["flight_operation"] = {
                "id": recent.pk,
                "name": str(
                    getattr(recent, 'name',
                    getattr(recent, 'operation_name',
                    getattr(recent, 'description', 'unknown'))) or ''
                ),
                "note": "most_recent_fallback"
            }
        print("Flight operation 'Rajasthan Corridor Inspection' not found by name")

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")

result_path = '/tmp/create_flight_operation_result.json'
with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)
print(f"Result written to {result_path}")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
