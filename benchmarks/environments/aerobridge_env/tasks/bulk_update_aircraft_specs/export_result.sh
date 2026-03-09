#!/bin/bash
# export_result.sh — Exports DB state and script info for verification

echo "=== Exporting bulk_update_aircraft_specs result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# 1. Check for Agent Script
# ============================================================
# Find any python script in home dir modified after task start
SCRIPT_PATH=$(find /home/ga -maxdepth 1 -name "*.py" -newermt "@$TASK_START" 2>/dev/null | head -n 1)
SCRIPT_EXISTS="false"
if [ -n "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    echo "Found agent script: $SCRIPT_PATH"
fi

# ============================================================
# 2. Query Database for Final State
# ============================================================
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

# Use a temp file for the python output to avoid mixing with stdout logging
PY_OUTPUT=$(mktemp)

/opt/aerobridge_venv/bin/python3 - > "$PY_OUTPUT" << 'PYEOF'
import os, sys, django, json
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
import django
django.setup()

from registry.models import Aircraft

data = {}
for ac in Aircraft.objects.all():
    data[ac.name] = {
        "mass": float(ac.mass) if ac.mass is not None else 0.0,
        "id": ac.id
    }

print(json.dumps(data))
PYEOF

DB_STATE=$(cat "$PY_OUTPUT")
rm "$PY_OUTPUT"

# ============================================================
# 3. Construct Final JSON
# ============================================================
JSON_OUTPUT=$(mktemp)
cat > "$JSON_OUTPUT" << EOF
{
    "script_created": $SCRIPT_EXISTS,
    "script_path": "$SCRIPT_PATH",
    "db_state": $DB_STATE,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $(date +%s)
}
EOF

# Move to final location (handling permissions)
cp "$JSON_OUTPUT" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$JSON_OUTPUT"

echo "Exported results to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="