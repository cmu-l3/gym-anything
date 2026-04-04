#!/bin/bash
# export_result.sh - Post-task data export for import_legacy_fleet

echo "=== Exporting Import Legacy Fleet results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Data using Django ORM
# We need to verify:
# - Operator exists
# - Aircraft exist and are linked to Operator
# - Aircraft details (Mass, Model, Manufacturer, Status) are correct

cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, json

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Aircraft, Company, Manufacturer

result = {
    "operator_exists": False,
    "operator_name": None,
    "aircraft_count": 0,
    "aircraft_records": [],
    "manufacturers_exist": [],
    "errors": []
}

target_op_name = "Rural Drone Services"

try:
    # Check Operator
    op = Company.objects.filter(name__iexact=target_op_name).first()
    if op:
        result["operator_exists"] = True
        result["operator_name"] = op.name
        
        # Check Linked Aircraft
        aircraft_qs = Aircraft.objects.filter(operator=op)
        result["aircraft_count"] = aircraft_qs.count()
        
        for ac in aircraft_qs:
            # Safe string conversion for fields
            mfr_name = str(ac.manufacturer) if ac.manufacturer else "None"
            status_str = str(ac.get_status_display()) if hasattr(ac, 'get_status_display') else str(ac.status)
            
            result["aircraft_records"].append({
                "registration": ac.registration_mark or f"ID-{ac.pk}",
                "model": str(ac.model),
                "mass": float(ac.mass) if ac.mass else 0.0,
                "manufacturer": mfr_name,
                "status": status_str
            })
    else:
        result["errors"].append(f"Operator '{target_op_name}' not found.")

    # Check Manufacturers (independent check)
    for m_name in ["DJI", "Parrot", "Skydio"]:
        if Manufacturer.objects.filter(name__icontains=m_name).exists():
            result["manufacturers_exist"].append(m_name)

except Exception as e:
    result["errors"].append(str(e))

# Write to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# 3. Permissions fix for verifier access
chmod 644 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="