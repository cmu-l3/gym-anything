#!/bin/bash
# export_result.sh — post_task hook for register_aircraft_model_chain

echo "=== Exporting register_aircraft_model_chain result ==="

DISPLAY=:1 scrot /tmp/register_aircraft_model_chain_end.png 2>/dev/null || true

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

from registry.models import Aircraft, AircraftAssembly, AircraftModel

try:
    with open('/tmp/aircraft_chain_baseline.json') as f:
        baseline = json.load(f)
except Exception:
    baseline = {}

result = {
    "task": "register_aircraft_model_chain",
    "baseline": baseline,
    "aircraft_model": None,
    "aircraft_assembly": None,
    "aircraft": None,
    "error": None
}

try:
    # Check AircraftModel
    am = AircraftModel.objects.filter(name='Nile Scout 200').first()
    if am:
        result["aircraft_model"] = {
            "id": str(am.id),
            "name": am.name,
            "category": am.category,
            "sub_category": am.sub_category,
            "series": am.series,
            "mass": am.mass,
            "type_certificate_id": str(am.type_certificate_id) if am.type_certificate_id else None
        }
        print(f"AircraftModel found: {am.name} (category={am.category})")

        # Check AircraftAssembly for this model
        aa = AircraftAssembly.objects.filter(aircraft_model=am).first()
        if aa:
            result["aircraft_assembly"] = {
                "id": str(aa.id),
                "model_name": am.name,
                "status": aa.status
            }
            print(f"AircraftAssembly found for Nile Scout 200 (status={aa.status})")
        else:
            print("AircraftAssembly for Nile Scout 200 NOT FOUND")
    else:
        print("AircraftModel 'Nile Scout 200' NOT FOUND")

    # Check Aircraft
    ac = Aircraft.objects.filter(name='NS-001').first()
    if ac:
        assembly_model_name = None
        if ac.final_assembly:
            try:
                assembly_model_name = ac.final_assembly.aircraft_model.name
            except Exception:
                pass
        result["aircraft"] = {
            "id": str(ac.id),
            "name": ac.name,
            "status": ac.status,
            "flight_controller_id": ac.flight_controller_id,
            "operator_id": str(ac.operator_id) if ac.operator_id else None,
            "final_assembly_id": str(ac.final_assembly_id) if ac.final_assembly_id else None,
            "assembly_model_name": assembly_model_name
        }
        print(f"Aircraft found: {ac.name} (assembly_model={assembly_model_name})")
    else:
        print("Aircraft 'NS-001' NOT FOUND")

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")

with open('/tmp/register_aircraft_model_chain_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
print("Result saved.")
PYEOF

echo "=== Export complete ==="
