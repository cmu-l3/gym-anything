#!/bin/bash
# export_result.sh — post_task hook for merge_drone_operators
set -e

echo "=== Exporting merge_drone_operators result ==="

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot "/tmp/task_final.png"

# Query current database state
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, json
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Company, Aircraft, Person

# Initialize result dict
result = {
    "source_exists": False,
    "target_exists": False,
    "target_aircraft_count": 0,
    "target_person_count": 0,
    "total_aircraft_count": 0,
    "total_person_count": 0,
    "error": None
}

try:
    # Check Source Company (Should be deleted)
    result["source_exists"] = Company.objects.filter(name='Valley UAV Logistics').exists()
    
    # Check Target Company (Should exist)
    target_qs = Company.objects.filter(name='Summit Drone Services')
    result["target_exists"] = target_qs.exists()
    
    if result["target_exists"]:
        target = target_qs.first()
        # Count assets assigned to Target
        result["target_aircraft_count"] = Aircraft.objects.filter(operator=target).count()
        result["target_person_count"] = Person.objects.filter(operator=target).count()
    
    # Count TOTAL assets in system (To ensure none were deleted)
    result["total_aircraft_count"] = Aircraft.objects.count()
    result["total_person_count"] = Person.objects.count()
    
except Exception as e:
    result["error"] = str(e)
    print(f"Error querying DB: {e}")

# Write to JSON
with open('/tmp/merge_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export data:")
print(json.dumps(result, indent=2))
PYEOF

# Move result to safe location for copy_from_env (though /tmp is usually fine)
mv /tmp/merge_result.json /tmp/task_result.json

echo "=== Export complete ==="