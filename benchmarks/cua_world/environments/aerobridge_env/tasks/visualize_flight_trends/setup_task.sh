#!/bin/bash
# setup_task.sh - Prepare environment for visualize_flight_trends

echo "=== Setting up visualize_flight_trends task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Aerobridge to be ready
wait_for_aerobridge 60 || echo "WARNING: Aerobridge server may not be ready"

# 2. Ensure we have interesting data to visualize
# Inject varied FlightPlan data so the chart isn't empty or boring
echo "Injecting historical flight plan data..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, random
from datetime import datetime, timedelta
from django.utils import timezone

sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

try:
    from gcs_operations.models import FlightPlan
    
    # Check current count
    count = FlightPlan.objects.count()
    print(f"Current FlightPlan count: {count}")
    
    # If we have fewer than 10 plans, generate some history
    if count < 10:
        print("Generating synthetic historical flight plans...")
        base_time = timezone.now()
        
        # Create plans distributed over the last 7 days
        for i in range(15):
            days_ago = random.randint(0, 6)
            # Create a dummy plan
            fp = FlightPlan(
                name=f"Historical Survey {i}",
                start_datetime=base_time - timedelta(days=days_ago),
                end_datetime=base_time - timedelta(days=days_ago, hours=2),
                # Minimal valid GeoJSON geometry (point)
                geometry={
                    "type": "Polygon",
                    "coordinates": [[[77.5, 12.9], [77.6, 12.9], [77.6, 13.0], [77.5, 13.0], [77.5, 12.9]]]
                }
            )
            fp.save()
            # Hack to update created_at if it's auto-now-add
            FlightPlan.objects.filter(pk=fp.pk).update(created_at=base_time - timedelta(days=days_ago))
            
        print(f"New FlightPlan count: {FlightPlan.objects.count()}")
    else:
        print("Sufficient data exists.")

except Exception as e:
    print(f"Data injection warning: {e}")
    # Don't fail the setup; agent might still be able to plot existing data
PYEOF

# 3. Clean up any previous run artifacts
rm -f /home/ga/flight_activity.png
rm -f /home/ga/generate_chart.py

# 4. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="