#!/bin/bash
# export_result.sh — post_task hook for create_survey_mission

echo "=== Exporting create_survey_mission result ==="

DISPLAY=:1 scrot /tmp/create_survey_mission_end.png 2>/dev/null || true

/opt/aerobridge_venv/bin/python3 << 'PYEOF'
import os, sys, django, json
sys.path.insert(0, '/opt/aerobridge')
os.environ['DJANGO_SETTINGS_MODULE'] = 'aerobridge.settings'
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

from gcs_operations.models import FlightPlan, FlightOperation

# Load baseline
try:
    with open('/tmp/survey_mission_baseline.json') as f:
        baseline = json.load(f)
except Exception:
    baseline = {'fp_count': 0, 'fo_count': 0, 'existing_plan_id': ''}

result = {
    "task": "create_survey_mission",
    "baseline": baseline,
    "current_fp_count": FlightPlan.objects.count(),
    "current_fo_count": FlightOperation.objects.count(),
    "flight_plan": None,
    "flight_operation": None,
    "error": None
}

try:
    # Find new flight plan
    fp = FlightPlan.objects.filter(name='Kolkata Port Survey').first()
    if fp:
        geo_json_val = fp.geo_json
        # Serialize geo_json for JSON output
        if hasattr(geo_json_val, '__iter__') and not isinstance(geo_json_val, str):
            geo_json_str = json.dumps(geo_json_val)
        else:
            geo_json_str = str(geo_json_val) if geo_json_val else ''

        result["flight_plan"] = {
            "id": str(fp.id),
            "name": fp.name,
            "is_editable": fp.is_editable,
            "geo_json": geo_json_str,
            "has_plan_file": bool(fp.plan_file_json)
        }
        print(f"Found FlightPlan: {fp.name} (id={fp.id})")
        print(f"  geo_json length: {len(geo_json_str)}")
    else:
        print("FlightPlan 'Kolkata Port Survey' NOT FOUND")

    # Find new flight operation
    fo = FlightOperation.objects.filter(name='Kolkata Port Inspection').first()
    if fo:
        result["flight_operation"] = {
            "id": str(fo.id),
            "name": fo.name,
            "flight_plan_id": str(fo.flight_plan_id) if fo.flight_plan_id else None,
            "drone_id": str(fo.drone_id) if fo.drone_id else None,
            "drone_name": fo.drone.name if fo.drone else None,
            "pilot_id": str(fo.pilot_id) if fo.pilot_id else None,
            "operator_id": str(fo.operator_id) if fo.operator_id else None,
            "type_of_operation": fo.type_of_operation
        }
        print(f"Found FlightOperation: {fo.name} (id={fo.id})")
        print(f"  flight_plan_id: {fo.flight_plan_id}")
        print(f"  drone: {fo.drone.name if fo.drone else None}")
    else:
        print("FlightOperation 'Kolkata Port Inspection' NOT FOUND")

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")

with open('/tmp/create_survey_mission_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
print("Result saved to /tmp/create_survey_mission_result.json")
PYEOF

echo "=== Export complete ==="
