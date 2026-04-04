#!/bin/bash
set -e

echo "=== Setting up analyze_battery_telemetry task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Aerobridge server is running
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Create Documents directory
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# Directory for hidden ground truth
mkdir -p /var/lib/aerobridge
chmod 755 /var/lib/aerobridge

# Generate Synthetic Flight Logs and Ground Truth
# We use the Django environment to create objects
echo "Generating synthetic flight logs..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, random
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
django.setup()

from registry.models import FlightLog, FlightOperation, Person, Aircraft

# 1. Clean existing logs to ensure a known state
FlightLog.objects.all().delete()
print("Cleared existing flight logs.")

# 2. Ensure dependencies exist
pilot = Person.objects.first()
if not pilot:
    pilot = Person.objects.create(first_name="Test", last_name="Pilot", email="test@example.com")

op = FlightOperation.objects.first()
if not op:
    op = FlightOperation.objects.create(
        name="Routine Patrol",
        operation_type="VLOS",
        pilot_in_command=pilot,
        start_datetime="2024-01-01T10:00:00Z",
        end_datetime="2024-01-01T11:00:00Z"
    )

# 3. Generate 50 logs with controlled BATT_END values
ground_truth = []
random.seed(42) # Deterministic generation

print("Creating 50 flight logs...")
for i in range(1, 51):
    # 30% chance of critical battery (< 15)
    if random.random() < 0.3:
        batt_end = random.randint(1, 14)
    else:
        batt_end = random.randint(15, 80)
        
    # Construct raw log string with some noise
    raw_log = (
        f"TAKEOFF,2024-01-15T09:30:00Z,28.61,77.20,0.0\n"
        f"WP1,2024-01-15T09:35:00Z,28.61,77.21,50.0\n"
        f"LAND,2024-01-15T09:55:00Z,28.61,77.20,0.0\n"
        f"BATT_START:98,BATT_END:{batt_end},TEMP_MAX:45,GPS_SATS:12"
    )
    
    log = FlightLog.objects.create(
        operation=op,
        raw_log=raw_log,
        is_submitted=True,
        signed_log=f"Signed content for log {i}"
    )
    
    # Store critical logs in ground truth
    if batt_end < 15:
        ground_truth.append(f"{log.id},{batt_end}")

# 4. Save Ground Truth to hidden file
gt_path = "/var/lib/aerobridge/battery_ground_truth.csv"
with open(gt_path, "w") as f:
    f.write("flight_log_id,batt_end_value\n")
    for line in ground_truth:
        f.write(line + "\n")

print(f"Ground truth saved to {gt_path} ({len(ground_truth)} critical flights)")
PYEOF

# Set permissions for ground truth so agent can't easily stumble on it (root only)
chmod 600 /var/lib/aerobridge/battery_ground_truth.csv

# Launch Firefox to Flight Logs page as a hint
echo "Launching Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8000/admin/registry/flightlog/' &"

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="