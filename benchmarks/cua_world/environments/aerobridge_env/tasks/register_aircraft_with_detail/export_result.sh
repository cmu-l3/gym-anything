#!/bin/bash
# export_result.sh — post_task hook for register_aircraft_with_detail

echo "=== Exporting register_aircraft_with_detail result ==="

DISPLAY=:1 scrot /tmp/register_aircraft_with_detail_end.png 2>/dev/null || true

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

from registry.models import Aircraft, AircraftDetail
from gcs_operations.models import FlightOperation

result = {
    "task": "register_aircraft_with_detail",
    "aircraft": None,
    "aircraft_detail": None,
    "flight_operation": None,
    "error": None
}

try:
    # Find Falcon Eye 3 aircraft
    ac = Aircraft.objects.filter(name='Falcon Eye 3').first()
    if ac:
        result["aircraft"] = {
            "id": str(ac.id),
            "name": ac.name,
            "flight_controller_id": ac.flight_controller_id,
            "status": ac.status,
            "operator_name": ac.operator.company.full_name if ac.operator and ac.operator.company else None,
            "manufacturer_name": ac.manufacturer.full_name if ac.manufacturer else None,
            "has_assembly": ac.final_assembly is not None
        }
        print(f"Aircraft found: {ac.name} (status={ac.status}, flt_ctrl={ac.flight_controller_id})")

        # Find AircraftDetail linked to Falcon Eye 3
        detail = AircraftDetail.objects.filter(aircraft=ac).first()
        if detail:
            result["aircraft_detail"] = {
                "id": str(detail.id),
                "aircraft_name": ac.name,
                "is_registered": detail.is_registered,
                "registration_mark": detail.registration_mark
            }
            print(f"AircraftDetail found: is_registered={detail.is_registered}, mark={detail.registration_mark}")
        else:
            print("AircraftDetail for Falcon Eye 3 NOT FOUND")
    else:
        print("Aircraft 'Falcon Eye 3' NOT FOUND")

    # Find maiden flight operation
    fo = FlightOperation.objects.filter(name='Falcon Eye 3 Maiden Flight').first()
    if fo:
        result["flight_operation"] = {
            "id": str(fo.id),
            "name": fo.name,
            "drone_name": fo.drone.name if fo.drone else None,
            "drone_id": str(fo.drone.id) if fo.drone else None,
            "operator_name": fo.operator.company.full_name if fo.operator and fo.operator.company else None,
            "pilot_name": fo.pilot.person.first_name + " " + fo.pilot.person.last_name if fo.pilot and fo.pilot.person else None
        }
        print(f"FlightOperation found: '{fo.name}', drone={fo.drone.name if fo.drone else None}")
    else:
        print("FlightOperation 'Falcon Eye 3 Maiden Flight' NOT FOUND")

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")

with open('/tmp/register_aircraft_with_detail_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
print("Result saved to /tmp/register_aircraft_with_detail_result.json")
PYEOF

echo "=== Export complete ==="
