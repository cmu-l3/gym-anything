#!/bin/bash
# setup_task.sh — pre_task hook for add_maintenance_activity

echo "=== Setting up add_maintenance_activity task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Aerobridge server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 2. Prepare Target Data
# Select a random aircraft from the database to be the target
echo "Selecting target aircraft..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django, random
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
    from registry.models import Aircraft, Activity
    
    # Get all active aircraft
    aircraft_list = list(Aircraft.objects.all())
    
    if not aircraft_list:
        print("ERROR: No aircraft found in database!")
        # Create a dummy one if needed (fallback)
        from registry.models import AircraftModel, Operator
        model = AircraftModel.objects.first()
        operator = Operator.objects.first()
        target = Aircraft.objects.create(name="Target Drone 01", aircraft_model=model, operator=operator)
    else:
        target = random.choice(aircraft_list)
    
    # Write info for Agent
    info_text = f"MAINTENANCE ORDER\n=================\n\nAIRCRAFT: {target.name}\nSERIAL: {target.flight_controller_id}\n\nTASK: Perform 100-Hour Scheduled Inspection log entry."
    with open('/home/ga/Documents/maintenance_task_info.txt', 'w') as f:
        f.write(info_text)
        
    # Write hidden info for Verifier
    with open('/tmp/target_aircraft_pk.txt', 'w') as f:
        f.write(str(target.pk))
        
    with open('/tmp/target_aircraft_name.txt', 'w') as f:
        f.write(str(target.name))

    print(f"Target selected: {target.name} (PK: {target.pk})")
    
    # Record initial Activity count
    print(f"Initial Activity count: {Activity.objects.count()}")
    with open('/tmp/initial_activity_count.txt', 'w') as f:
        f.write(str(Activity.objects.count()))

except Exception as e:
    print(f"Setup error: {e}")
    # Fallback to ensure task doesn't completely fail setup
    with open('/home/ga/Documents/maintenance_task_info.txt', 'w') as f:
        f.write("AIRCRAFT: Any Available\n")
    with open('/tmp/target_aircraft_pk.txt', 'w') as f:
        f.write("ANY")
PYEOF

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents/maintenance_task_info.txt

# 3. Record timestamp
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

# 4. Launch Firefox to Admin Panel
echo "Launching Firefox..."
pkill -9 -f firefox 2>/dev/null || true
# Clean profile locks
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock
       
# Launch
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/' &"

# Wait for window
sleep 5
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox"; then
        DISPLAY=:1 wmctrl -a "Mozilla Firefox"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="