#!/bin/bash
set -e
echo "=== Setting up extend_aircraft_model task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Record initial database schema state
# We need to prove the column didn't exist before the agent started
echo "Recording initial schema..."
sqlite3 "${AEROBRIDGE_DB}" "PRAGMA table_info(registry_aircraft);" > /tmp/initial_schema.txt 2>/dev/null || true

# Safety check: if column already exists (from a previous failed run), clean it up?
# In a fresh environment, this shouldn't happen, but good for robustness.
if grep -q "max_altitude_m" /tmp/initial_schema.txt; then
    echo "WARNING: max_altitude_m already exists. Attempting to reset..."
    # (Optional cleanup logic could go here, but for now we just warn)
fi

# 2. Record initial aircraft count
# Used to verify if ALL records get updated later
echo "Recording initial aircraft count..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

INITIAL_COUNT=$(/opt/aerobridge_venv/bin/python3 -c "
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()
from registry.models import Aircraft
print(Aircraft.objects.count())
" 2>/dev/null || echo "0")

echo "$INITIAL_COUNT" > /tmp/initial_aircraft_count.txt
echo "Initial aircraft count: $INITIAL_COUNT"

# 3. Record existing migration files
# To distinguish new migrations created by the agent
ls -1 /opt/aerobridge/registry/migrations/*.py > /tmp/initial_migrations.txt 2>/dev/null || true

# 4. Ensure server is running and accessible
ensure_server_running
wait_for_aerobridge 60

# 5. Launch Firefox to the Aircraft admin page
# This helps the agent see the starting state (no field visible)
launch_firefox "http://localhost:8000/admin/registry/aircraft/"
sleep 5

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="