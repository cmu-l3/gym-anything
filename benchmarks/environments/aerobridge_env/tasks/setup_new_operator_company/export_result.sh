#!/bin/bash
# export_result.sh — post_task hook for setup_new_operator_company

echo "=== Exporting setup_new_operator_company result ==="

DISPLAY=:1 scrot /tmp/setup_new_operator_company_end.png 2>/dev/null || true

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

from registry.models import Company, Operator

result = {
    "task": "setup_new_operator_company",
    "company": None,
    "operator": None,
    "error": None
}

try:
    # Find BlueSky company
    comp = Company.objects.filter(full_name='BlueSky Robotics Pvt Ltd').first()
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

        # Find operator linked to this company
        op = Operator.objects.filter(company=comp).first()
        if op:
            activities = sorted(list(op.authorized_activities.values_list('name', flat=True)))
            auths = sorted(list(op.operational_authorizations.values_list('title', flat=True)))
            result["operator"] = {
                "id": str(op.id),
                "company_full_name": comp.full_name,
                "operator_type": op.operator_type,
                "authorized_activities": activities,
                "operational_authorizations": auths
            }
            print(f"Operator found: type={op.operator_type}, activities={activities}, auths={auths}")
        else:
            print("Operator for BlueSky NOT FOUND")
    else:
        print("Company 'BlueSky Robotics Pvt Ltd' NOT FOUND")
        # Try partial match
        partials = Company.objects.filter(full_name__icontains='BlueSky')
        if partials.exists():
            print(f"Found partial matches: {[c.full_name for c in partials]}")

except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")

with open('/tmp/setup_new_operator_company_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
print("Result saved to /tmp/setup_new_operator_company_result.json")
PYEOF

echo "=== Export complete ==="
