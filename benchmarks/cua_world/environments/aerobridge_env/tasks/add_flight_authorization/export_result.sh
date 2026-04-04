#!/bin/bash
# export_result.sh — post_task hook for add_flight_authorization

echo "=== Exporting add_flight_authorization result ==="

# 1. Source utils and capture final screenshot
source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_final_state.png

# 2. Read baseline data
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")
COUNT_BEFORE=$(cat /tmp/auth_count_before 2>/dev/null || echo "0")

# 3. Query database using Django to get the result details
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os, sys, django, json
from datetime import datetime

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

result = {
    "task_start_time": "${TASK_START}",
    "count_before": int("${COUNT_BEFORE}" or 0),
    "current_count": 0,
    "record_found": False,
    "record": None,
    "error": None
}

try:
    from registry.models import Authorization
    
    # Update current count
    result["current_count"] = Authorization.objects.count()
    
    # Search for the specific record
    # We look for the title primarily
    qs = Authorization.objects.filter(title__icontains='Mumbai Port Area BVLOS')
    
    if qs.exists():
        # Get the most recently created one if multiple match
        auth = qs.order_by('-created_at').first()
        result["record_found"] = True
        
        # Extract fields for verification
        result["record"] = {
            "id": auth.id,
            "title": auth.title,
            "operation_max_height": auth.operation_max_height,
            "operation_ceiling": auth.operation_ceiling,
            "permit_to_fly_above_crowd": auth.permit_to_fly_above_crowd,
            "operator_id": auth.operator_id,
            # Handle dates safely (convert to string)
            "start_date": str(auth.start_date) if auth.start_date else None,
            "end_date": str(auth.end_date) if auth.end_date else None,
            "created_at": str(auth.created_at)
        }
    else:
        # Fallback: check if ANY record was created since start to give partial feedback
        # This helps debug if they created a record but named it wrong
        if result["current_count"] > result["count_before"]:
            latest = Authorization.objects.order_by('-created_at').first()
            if latest:
                result["latest_record_title"] = latest.title
                
except Exception as e:
    result["error"] = str(e)
    print(f"Error exporting result: {e}")

# Save to JSON file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete. Result:")
print(json.dumps(result, indent=2))
PYEOF

# 4. Handle permissions so verifier can read it
chmod 644 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="