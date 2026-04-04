#!/bin/bash
# export_result.sh — post_task hook for update_operator_authorizations

echo "=== Exporting update_operator_authorizations result ==="

DISPLAY=:1 scrot /tmp/update_operator_authorizations_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")

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

from registry.models import Operator

result = {
    "task": "update_operator_authorizations",
    "operator": None,
    "error": None
}

try:
    op = None
    for o in Operator.objects.select_related('company').all():
        if o.company.full_name == 'Electric Inspection':
            op = o
            break

    if op:
        activities = sorted(list(op.authorized_activities.values_list('name', flat=True)))
        auths = sorted(list(op.operational_authorizations.values_list('title', flat=True)))
        result["operator"] = {
            "id": str(op.id),
            "company_full_name": op.company.full_name,
            "operator_type": op.operator_type,
            "authorized_activities": activities,
            "operational_authorizations": auths
        }
        print(f"Electric Inspection operator state:")
        print(f"  operator_type: {op.operator_type}")
        print(f"  activities: {activities}")
        print(f"  authorizations: {auths}")
    else:
        result["error"] = "Electric Inspection operator not found"
        print("ERROR: Electric Inspection operator not found")
except Exception as e:
    result["error"] = str(e)
    print(f"Export error: {e}")

with open('/tmp/update_operator_authorizations_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/update_operator_authorizations_result.json")
PYEOF

echo "=== Export complete ==="
