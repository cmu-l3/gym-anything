#!/bin/bash
# setup_task.sh — pre_task hook for calculate_fleet_utilization
# Sets up companies and flight plans with specific dates/durations.

echo "=== Setting up calculate_fleet_utilization task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Aerobridge server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Inject data: Companies and Flight Plans
echo "Injecting flight plan data..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
from datetime import datetime, timedelta
import pytz

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip("'").strip('"'))
django.setup()

try:
    from registry.models import Company, Operator
    from gcs_operations.models import FlightPlan

    # 1. Setup Companies / Operators
    # Ensure SkyHigh Surveyors exists
    company_sky, _ = Company.objects.get_or_create(
        full_name='SkyHigh Surveyors',
        defaults={'country': 'US'}
    )
    # Ensure Other Corp exists (distractor)
    company_other, _ = Company.objects.get_or_create(
        full_name='Other Corp',
        defaults={'country': 'US'}
    )
    
    # Ensure Operators exist for these companies
    # (FlightPlan usually links to Operator, or Company depending on version. 
    # Aerobridge models often link FlightPlan to 'operator' which is a separate model linked to Company)
    # Let's check if Operator model exists and link it.
    
    op_sky, _ = Operator.objects.get_or_create(company=company_sky)
    op_other, _ = Operator.objects.get_or_create(company=company_other)

    # 2. Clear existing Flight Plans for these operators to ensure clean state
    FlightPlan.objects.filter(operator=op_sky).delete()
    FlightPlan.objects.filter(operator=op_other).delete()

    # 3. Create Flight Plans
    # We need timezone-aware datetimes
    tz = pytz.UTC

    # FP1: Oct 5, 2023, 10:00 - 10:45 (45 mins) -> INCLUDE
    # Status: use default (usually 1 or 0)
    fp1 = FlightPlan.objects.create(
        name="Survey Flight A - Oct 5",
        operator=op_sky,
        start_datetime=datetime(2023, 10, 5, 10, 0, 0, tzinfo=tz),
        end_datetime=datetime(2023, 10, 5, 10, 45, 0, tzinfo=tz),
        geometry={} # Empty geometry is fine for this task
    )

    # FP2: Oct 12, 2023, 14:00 - 15:30 (90 mins) -> INCLUDE
    fp2 = FlightPlan.objects.create(
        name="Survey Flight B - Oct 12",
        operator=op_sky,
        start_datetime=datetime(2023, 10, 12, 14, 0, 0, tzinfo=tz),
        end_datetime=datetime(2023, 10, 12, 15, 30, 0, tzinfo=tz),
        geometry={}
    )

    # FP3: Nov 1, 2023, 10:00 - 11:00 (60 mins) -> EXCLUDE (Wrong Month)
    fp3 = FlightPlan.objects.create(
        name="Survey Flight C - Nov 1",
        operator=op_sky,
        start_datetime=datetime(2023, 11, 1, 10, 0, 0, tzinfo=tz),
        end_datetime=datetime(2023, 11, 1, 11, 0, 0, tzinfo=tz),
        geometry={}
    )

    # FP4: Oct 15, 2023, 12:00 - 13:00 (60 mins) -> EXCLUDE (Wrong Operator)
    fp4 = FlightPlan.objects.create(
        name="Other Corp Flight - Oct 15",
        operator=op_other,
        start_datetime=datetime(2023, 10, 15, 12, 0, 0, tzinfo=tz),
        end_datetime=datetime(2023, 10, 15, 13, 0, 0, tzinfo=tz),
        geometry={}
    )

    print(f"Created 4 flight plans. Target duration: 45 + 90 = 135 mins.")

except Exception as e:
    print(f"Setup error: {e}")
    import traceback
    traceback.print_exc()

PYEOF

# Record task start time
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

# Launch Firefox to Flight Plans list
echo "Launching Firefox to Flight Plans..."
launch_firefox "http://localhost:8000/admin/gcs_operations/flightplan/"

# Take initial screenshot
sleep 8
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="