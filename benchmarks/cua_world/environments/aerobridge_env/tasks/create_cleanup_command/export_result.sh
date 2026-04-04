#!/bin/bash
echo "=== Exporting Task Result ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
COMMAND_FILE="/opt/aerobridge/registry/management/commands/close_expired_plans.py"
INIT_FILE="/opt/aerobridge/registry/management/commands/__init__.py"

# Check file stats
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$COMMAND_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$COMMAND_FILE")
    FILE_MTIME=$(stat -c%Y "$COMMAND_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check init file (needed for command to work)
INIT_EXISTS="false"
if [ -f "$INIT_FILE" ]; then
    INIT_EXISTS="true"
fi

# 3. Check DB State of Canaries
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, json
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

result = {
    "canary_states": {},
    "db_check_error": None
}

try:
    # Handle model import
    try:
        from registry.models import FlightPlan
    except ImportError:
        from gcs_operations.models import FlightPlan

    # Load IDs
    if os.path.exists('/tmp/canaries.json'):
        with open('/tmp/canaries.json') as f:
            ids = json.load(f)
            
        c1 = FlightPlan.objects.get(id=ids['expired_active_id'])
        c2 = FlightPlan.objects.get(id=ids['future_active_id'])
        c3 = FlightPlan.objects.get(id=ids['expired_closed_id'])
        
        result["canary_states"] = {
            "expired_active_status": c1.status,
            "future_active_status": c2.status,
            "expired_closed_status": c3.status
        }
    else:
        result["db_check_error"] = "Canary ID file missing"

except Exception as e:
    result["db_check_error"] = str(e)

# Save intermediate python result
with open('/tmp/py_export.json', 'w') as f:
    json.dump(result, f)
PYEOF

# 4. Combine into final JSON
# We use python to merge shell vars and the python output safely
python3 -c "
import json
import os

try:
    with open('/tmp/py_export.json') as f:
        py_data = json.load(f)
except:
    py_data = {}

final = {
    'task_start': $TASK_START,
    'file_exists': '$FILE_EXISTS' == 'true',
    'file_created_during_task': '$FILE_CREATED_DURING_TASK' == 'true',
    'init_exists': '$INIT_EXISTS' == 'true',
    'file_size': int('$FILE_SIZE'),
    'canary_states': py_data.get('canary_states', {}),
    'db_error': py_data.get('db_check_error')
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final, f, indent=2)
"

# 5. Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json