#!/bin/bash
# export_result.sh — post_task hook for onboard_new_operator_fleet

echo "=== Exporting onboard_new_operator_fleet result ==="

DISPLAY=:1 scrot /tmp/onboard_new_operator_fleet_end.png 2>/dev/null || true

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

from registry.models import Company, Operator, Person, Pilot, Aircraft
from gcs_operations.models import FlightPlan, FlightOperation

result = {
    "task": "onboard_new_operator_fleet",
    "company": None,
    "operator": None,
    "persons": [],
    "pilots": [],
    "aircraft": [],
    "flight_plan": None,
    "flight_operation": None,
    "error": None
}

try:
    # ── Company ──────────────────────────────────────────────────────────────
    comp = Company.objects.filter(full_name='Horizon Aerial Services Pvt Ltd').first()
    if not comp:
        # Try partial match
        comp = Company.objects.filter(full_name__icontains='Horizon Aerial').first()
    if comp:
        result["company"] = {
            "id": str(comp.id),
            "full_name": comp.full_name,
            "common_name": comp.common_name,
            "role": comp.role,
            "country": comp.country,
            "email": comp.email,
            "website": comp.website
        }
        print(f"Company found: {comp.full_name} (role={comp.role}, country={comp.country})")

        # ── Operator ─────────────────────────────────────────────────────────
        op = Operator.objects.filter(company=comp).first()
        if op:
            activities = sorted(list(
                op.authorized_activities.values_list('name', flat=True)
            ))
            auths = sorted(list(
                op.operational_authorizations.values_list('title', flat=True)
            ))
            result["operator"] = {
                "id": str(op.id),
                "company_full_name": comp.full_name,
                "operator_type": op.operator_type,
                "authorized_activities": activities,
                "operational_authorizations": auths
            }
            print(f"Operator found: type={op.operator_type}, "
                  f"activities={activities}, auths={auths}")
        else:
            print("Operator for Horizon Aerial NOT FOUND")
    else:
        print("Company 'Horizon Aerial Services Pvt Ltd' NOT FOUND")
        partials = Company.objects.filter(full_name__icontains='Horizon')
        if partials.exists():
            print(f"Partial matches: {[c.full_name for c in partials]}")

    # ── Persons ──────────────────────────────────────────────────────────────
    for first, last in [('Arjun', 'Mehta'), ('Priya', 'Sharma')]:
        p = Person.objects.filter(first_name=first, last_name=last).first()
        if not p:
            # Fallback: search by email prefix
            p = Person.objects.filter(
                email__istartswith=first.lower()
            ).first()
        if p:
            result["persons"].append({
                "first_name": p.first_name,
                "last_name": p.last_name,
                "email": p.email
            })
            print(f"Person found: {p.first_name} {p.last_name} ({p.email})")
        else:
            print(f"Person NOT FOUND: {first} {last}")

    # ── Pilots ───────────────────────────────────────────────────────────────
    for first, last in [('Arjun', 'Mehta'), ('Priya', 'Sharma')]:
        pilot = Pilot.objects.filter(
            person__first_name=first, person__last_name=last
        ).first()
        if pilot:
            op_company = (pilot.operator.company.full_name
                          if pilot.operator and pilot.operator.company
                          else None)
            result["pilots"].append({
                "person_name": (f"{pilot.person.first_name} "
                                f"{pilot.person.last_name}"),
                "operator_company": op_company
            })
            print(f"Pilot found: {pilot.person.first_name} "
                  f"{pilot.person.last_name} -> {op_company}")
        else:
            print(f"Pilot NOT FOUND for: {first} {last}")

    # ── Aircraft ─────────────────────────────────────────────────────────────
    for name in ['HA-Scout-01', 'HA-Scout-02']:
        ac = Aircraft.objects.filter(name=name).first()
        if ac:
            op_company = (ac.operator.company.full_name
                          if ac.operator and ac.operator.company
                          else None)
            mfr_name = (ac.manufacturer.full_name
                        if ac.manufacturer else None)
            result["aircraft"].append({
                "name": ac.name,
                "flight_controller_id": ac.flight_controller_id,
                "status": ac.status,
                "operator_company": op_company,
                "manufacturer_name": mfr_name,
                "has_assembly": ac.final_assembly is not None
            })
            print(f"Aircraft found: {ac.name} (operator={op_company})")
        else:
            print(f"Aircraft NOT FOUND: {name}")

    # ── FlightPlan ───────────────────────────────────────────────────────────
    fp = FlightPlan.objects.filter(name='Mumbai Harbor Survey').first()
    if fp:
        geo_val = fp.geo_json
        if hasattr(geo_val, '__iter__') and not isinstance(geo_val, str):
            geo_str = json.dumps(geo_val)
        else:
            geo_str = str(geo_val) if geo_val else ''
        result["flight_plan"] = {
            "id": str(fp.id),
            "name": fp.name,
            "geo_json": geo_str,
            "has_plan_file": bool(
                fp.plan_file_json and len(str(fp.plan_file_json)) > 2
            )
        }
        print(f"FlightPlan found: {fp.name} "
              f"(geo_json len={len(geo_str)})")
    else:
        print("FlightPlan 'Mumbai Harbor Survey' NOT FOUND")

    # ── FlightOperation ──────────────────────────────────────────────────────
    fo = FlightOperation.objects.filter(
        name='HA Fleet Certification Flight'
    ).first()
    if fo:
        pilot_name = None
        if fo.pilot and fo.pilot.person:
            pilot_name = (f"{fo.pilot.person.first_name} "
                          f"{fo.pilot.person.last_name}")
        op_company = (fo.operator.company.full_name
                      if fo.operator and fo.operator.company
                      else None)
        result["flight_operation"] = {
            "id": str(fo.id),
            "name": fo.name,
            "drone_name": fo.drone.name if fo.drone else None,
            "pilot_name": pilot_name,
            "operator_company": op_company,
            "flight_plan_name": (fo.flight_plan.name
                                 if fo.flight_plan else None),
            "purpose": fo.purpose.name if fo.purpose else None,
            "type_of_operation": fo.type_of_operation
        }
        print(f"FlightOperation found: {fo.name} "
              f"(drone={fo.drone.name if fo.drone else 'N/A'})")
    else:
        print("FlightOperation 'HA Fleet Certification Flight' NOT FOUND")

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")
    import traceback
    traceback.print_exc()

with open('/tmp/onboard_new_operator_fleet_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
print("Result saved to /tmp/onboard_new_operator_fleet_result.json")
PYEOF

echo "=== Export complete ==="
