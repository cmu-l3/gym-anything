#!/bin/bash
# export_result.sh — post_task hook for add_maintenance_activity

echo "=== Exporting add_maintenance_activity result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather context data
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "unknown")
INITIAL_COUNT=$(cat /tmp/initial_activity_count.txt 2>/dev/null || echo "0")
TARGET_PK=$(cat /tmp/target_aircraft_pk.txt 2>/dev/null || echo "0")
TARGET_NAME=$(cat /tmp/target_aircraft_name.txt 2>/dev/null || echo "Unknown")

CONFIRMATION_FILE="/home/ga/Documents/activity_confirmation.txt"
CONFIRMATION_EXISTS="false"
CONFIRMATION_CONTENT=""

if [ -f "$CONFIRMATION_FILE" ]; then
    CONFIRMATION_EXISTS="true"
    CONFIRMATION_CONTENT=$(cat "$CONFIRMATION_FILE" | head -n 1)
fi

# 3. Export DB State using Python/Django
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << PYEOF
import os, sys, django, json
from datetime import datetime
import dateutil.parser

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
    "initial_count": int("${INITIAL_COUNT}"),
    "target_pk": "${TARGET_PK}",
    "target_name": "${TARGET_NAME}",
    "confirmation_file_exists": "${CONFIRMATION_EXISTS}" == "true",
    "confirmation_content": "${CONFIRMATION_CONTENT}",
    "new_activities": [],
    "final_count": 0
}

try:
    from registry.models import Activity
    
    result["final_count"] = Activity.objects.count()
    
    # Find activities created after task start
    # Note: SQLite stores datetimes, need careful comparison or just use ID diff if strictly sequential
    # We'll fetch all activities with ID > initial count (approximation) or check timestamps if available
    
    # Strategy: Get all activities, check created_at/updated_at if available, 
    # or just look at the last few records if created_at isn't reliable/present.
    # Aerobridge Activity model usually has a timestamp or date field.
    
    # Let's inspect the last few entries
    recent_activities = Activity.objects.order_by('-id')[:5]
    
    for act in recent_activities:
        # Check if this looks like the agent's work
        # Basic field dumping
        act_data = {
            "id": act.pk,
            "name": getattr(act, 'name', '') or '',
            "type": str(getattr(act, 'activity_type', '')),
            "aircraft_id": str(getattr(act.aircraft, 'pk', '')) if hasattr(act, 'aircraft') and act.aircraft else None,
            "aircraft_name": str(getattr(act.aircraft, 'name', '')) if hasattr(act, 'aircraft') and act.aircraft else None,
        }
        
        # Determine if created during task
        # Ideally check created_at, but if relying on IDs:
        # If we had N items, any item with ID > N *might* be new (auto-increment)
        # However, checking 'name' content is safer for verification logic
        result["new_activities"].append(act_data)

except Exception as e:
    result["error"] = str(e)

# Save to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="