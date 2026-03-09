#!/bin/bash
# setup_task.sh — pre_task hook for sql_fleet_cross_reference_report

echo "=== Setting up SQL Fleet Report Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Install sqlite3 CLI if not present (Aerobridge installs libsqlite3-dev but maybe not the CLI tool)
if ! command -v sqlite3 &> /dev/null; then
    echo "Installing sqlite3 CLI..."
    apt-get update -qq && apt-get install -y sqlite3 -qq
fi

# 2. Ensure Aerobridge server is ready (to ensure DB is populated/migrated)
wait_for_aerobridge 60 || echo "WARNING: Aerobridge server may not be ready"

# 3. Clean up any previous report
rm -f /home/ga/Documents/fleet_sql_report.txt

# 4. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 5. Record Ground Truth Data (using Django ORM to get accurate counts/names for verification)
# We calculate what the SQL report SHOULD contain
echo "Calculating ground truth..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, json
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import Aircraft, Company, Person

gt = {
    "aircraft_count": Aircraft.objects.count(),
    "person_count": Person.objects.count(),
    "company_count": Company.objects.count(),
    "manufacturers": list(Company.objects.filter(aircraft_manufacturer__isnull=False).distinct().values_list('full_name', flat=True)),
    "operators": list(Company.objects.filter(aircraft_operator__isnull=False).distinct().values_list('full_name', flat=True)),
    "sample_persons": list(Person.objects.values_list('last_name', flat=True)[:5])
}

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(gt, f)
    
print(f"Ground truth recorded: {gt['aircraft_count']} aircraft, {gt['person_count']} people")
PYEOF

# 6. Open a terminal for the agent (since this is a CLI task)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
    sleep 2
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="