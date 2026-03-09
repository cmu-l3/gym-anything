#!/bin/bash
set -e
echo "=== Exporting extend_aircraft_model results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ============================================================
# Check 1: Migration File
# ============================================================
echo "Checking for new migration file..."
NEW_MIGRATION_FILE=""
MIGRATION_CREATED_DURING_TASK="false"

# Find any migration file containing 'max_altitude_m'
# We look for files NOT in the initial list
CURRENT_MIGRATIONS=$(ls -1 /opt/aerobridge/registry/migrations/*.py 2>/dev/null)
INITIAL_MIGRATIONS_FILE="/tmp/initial_migrations.txt"

for f in $CURRENT_MIGRATIONS; do
    if ! grep -qF "$f" "$INITIAL_MIGRATIONS_FILE" 2>/dev/null; then
        # This is a new file. Check content.
        if grep -q "max_altitude_m" "$f" 2>/dev/null; then
            NEW_MIGRATION_FILE="$f"
            # Check modification time
            MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
            if [ "$MTIME" -ge "$TASK_START" ]; then
                MIGRATION_CREATED_DURING_TASK="true"
            fi
            break
        fi
    fi
done

# Fallback: if they modified an existing migration (bad practice but possible), check timestamps
if [ -z "$NEW_MIGRATION_FILE" ]; then
    FOUND=$(grep -l "max_altitude_m" /opt/aerobridge/registry/migrations/*.py 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        NEW_MIGRATION_FILE="$FOUND"
        MTIME=$(stat -c %Y "$FOUND" 2>/dev/null || echo "0")
        if [ "$MTIME" -ge "$TASK_START" ]; then
            MIGRATION_CREATED_DURING_TASK="true"
        fi
    fi
fi

# ============================================================
# Check 2 & 3: Database Schema and Data Integrity
# ============================================================
echo "Checking database schema and data..."

cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

# Run a python script to inspect the models and data via Django ORM
# This is more robust than raw SQL for verifying 'blank=True' etc.
/opt/aerobridge_venv/bin/python3 - << PYEOF > /tmp/db_inspection.json
import os, sys, django, json
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

result = {
    "column_exists": False,
    "is_integer": False,
    "allows_null": False,
    "total_aircraft": 0,
    "count_with_120": 0,
    "count_null": 0,
    "count_other": 0
}

try:
    from registry.models import Aircraft
    
    # 1. Introspect model field
    try:
        field = Aircraft._meta.get_field('max_altitude_m')
        result["column_exists"] = True
        result["is_integer"] = field.get_internal_type() == 'IntegerField'
        result["allows_null"] = field.null
    except Exception:
        pass

    # 2. Check data
    qs = Aircraft.objects.all()
    result["total_aircraft"] = qs.count()
    
    if result["column_exists"]:
        result["count_with_120"] = qs.filter(max_altitude_m=120).count()
        result["count_null"] = qs.filter(max_altitude_m__isnull=True).count()
        result["count_other"] = qs.exclude(max_altitude_m=120).exclude(max_altitude_m__isnull=True).count()

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# ============================================================
# Check 4: Admin Configuration
# ============================================================
echo "Checking admin configuration..."
ADMIN_FILE="/opt/aerobridge/registry/admin.py"
ADMIN_UPDATED="false"

if [ -f "$ADMIN_FILE" ]; then
    # Simple check: does the file contain the field name?
    if grep -q "max_altitude_m" "$ADMIN_FILE"; then
        ADMIN_UPDATED="true"
    fi
fi

# ============================================================
# Check 5: Server Status
# ============================================================
echo "Checking server status..."
SERVER_STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8000/admin/" --max-time 5 2>/dev/null || echo "000")

# ============================================================
# Compile Final JSON
# ============================================================
echo "Compiling results..."

DB_INSPECTION=$(cat /tmp/db_inspection.json 2>/dev/null || echo "{}")

# Create JSON using jq or python to ensure valid format
/opt/aerobridge_venv/bin/python3 -c "
import json
import sys

try:
    db_data = json.loads('''$DB_INSPECTION''')
except:
    db_data = {}

final = {
    'migration_file_exists': bool('$NEW_MIGRATION_FILE'),
    'migration_created_during_task': '$MIGRATION_CREATED_DURING_TASK' == 'true',
    'db_check': db_data,
    'admin_updated': '$ADMIN_UPDATED' == 'true',
    'server_status_code': '$SERVER_STATUS_CODE',
    'task_timestamp': $TASK_END
}
print(json.dumps(final, indent=2))
" > /tmp/task_result.json

# Cleanup and secure
chmod 666 /tmp/task_result.json
echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json