#!/bin/bash
# export_result.sh — post_task hook for process_warranty_replacement

echo "=== Exporting process_warranty_replacement result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export data using Django ORM
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
    "crashed_found": False,
    "crashed_renamed": False,
    "crashed_status": "unknown",
    "replacement_found": False,
    "replacement_operator": None,
    "replacement_manufacturer": None,
    "expected_operator": "SkyHigh Services",
    "expected_manufacturer": "DroneCorp Global"
}

try:
    # 1. Check Crashed Aircraft
    # It might be renamed, so we search by ID if we had it, or broad search
    # Since we don't have ID persisted easily in this script, we look for variants
    
    # Look for the original registration
    original = Aircraft.objects.filter(registration='SH-CRASH-001').first()
    
    # Look for the modified registration
    modified = Aircraft.objects.filter(registration__icontains='SH-CRASH-001').filter(registration__icontains='WRITE-OFF').first()
    
    crashed_obj = modified if modified else original
    
    if crashed_obj:
        result["crashed_found"] = True
        reg = crashed_obj.registration
        result["crashed_reg"] = reg
        result["crashed_renamed"] = "WRITE-OFF" in reg.upper()
        # Check status field (could be 'status' charfield or 'is_active' boolean depending on version)
        if hasattr(crashed_obj, 'status'):
            result["crashed_status"] = str(crashed_obj.status)
        elif hasattr(crashed_obj, 'is_active'):
            result["crashed_status"] = "active" if crashed_obj.is_active else "inactive"
            
    # 2. Check Replacement Aircraft
    repl = Aircraft.objects.filter(registration='SH-REPL-002').first()
    if repl:
        result["replacement_found"] = True
        result["replacement_operator"] = repl.operator.name if repl.operator else None
        result["replacement_manufacturer"] = repl.manufacturer.name if repl.manufacturer else None

except Exception as e:
    result["error"] = str(e)
    print(f"Error during export: {e}")

# Save to JSON
with open('/tmp/warranty_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export data:")
print(json.dumps(result, indent=2))
PYEOF

# Ensure permissions
chmod 666 /tmp/warranty_result.json 2>/dev/null || true

echo "=== Export complete ==="