#!/bin/bash
# setup_task.sh — pre_task hook for register_aircraft
# Sets up the task: removes any pre-existing test aircraft, records baseline,
# launches Firefox to the admin panel ready for the agent.

echo "=== Setting up register_aircraft task ==="

# Load shared utilities
# Note: using 'source' with set -e disabled for this sourcing
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ============================================================
# 1. Wait for Aerobridge server to be ready
# ============================================================
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# ============================================================
# 2. Remove any pre-existing 'Phoenix Mk3' aircraft and prepare
#    a dedicated AircraftAssembly for the task
# ============================================================
echo "Removing any pre-existing test aircraft 'Phoenix Mk3'..."
cd /opt/aerobridge
set -a
source /opt/aerobridge/.env 2>/dev/null || true
set +a

/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
import os, sys, django
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
    from registry.models import Aircraft, AircraftAssembly, AircraftModel
    # Remove any pre-existing Phoenix Mk3 aircraft
    deleted, _ = Aircraft.objects.filter(name='Phoenix Mk3').delete()
    if deleted:
        print(f"Removed {deleted} existing 'Phoenix Mk3' aircraft record(s)")
    else:
        print("No pre-existing 'Phoenix Mk3' aircraft found (clean)")
    print(f"Current aircraft count: {Aircraft.objects.count()}")
    # Ensure a free AircraftAssembly with status=2 (Complete) is available.
    # CRITICAL: final_assembly field uses limit_choices_to={'status':2}, so only
    # status=2 assemblies appear in the Django admin dropdown. Create a new
    # unassigned status=2 assembly for the agent to select.
    model = AircraftModel.objects.first()
    if model:
        # Find any existing status=2 assemblies not yet assigned to any aircraft
        free_assemblies = []
        for asm in AircraftAssembly.objects.filter(status=2):
            try:
                Aircraft.objects.get(final_assembly=asm)
            except Aircraft.DoesNotExist:
                free_assemblies.append(asm)
        # Delete extra free assemblies (from previous task runs), keep at most 0
        for asm in free_assemblies:
            asm.delete()
            print(f"Deleted leftover free assembly: pk={asm.pk}")
        # Create exactly one new free status=2 assembly for this task
        assembly = AircraftAssembly.objects.create(status=2, aircraft_model=model)
        print(f"Created new task assembly: status='Complete' (status=2), pk={assembly.pk}")
        print(f"Total status=2 assemblies now: {AircraftAssembly.objects.filter(status=2).count()}")
    else:
        print("WARNING: No AircraftModel found!")
except Exception as e:
    print(f"Cleanup note: {e}")
    import traceback; traceback.print_exc()
PYEOF

# ============================================================
# 3. Record initial state for anti-gaming verification
# ============================================================
echo "Recording task start state..."
record_task_start 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

AIRCRAFT_COUNT_BEFORE=$(/opt/aerobridge_venv/bin/python3 -c "
import os, sys, django
sys.path.insert(0, '/opt/aerobridge')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'aerobridge.settings')
with open('/opt/aerobridge/.env') as f:
    for line in f:
        line = line.strip()
        if '=' in line and not line.startswith('#'):
            k, _, v = line.partition('=')
            os.environ.setdefault(k, v.strip(\"'\").strip('\"'))
django.setup()
from registry.models import Aircraft
print(Aircraft.objects.count())
" 2>/dev/null || echo "0")
echo "$AIRCRAFT_COUNT_BEFORE" > /tmp/aircraft_count_before
echo "Aircraft count before task: ${AIRCRAFT_COUNT_BEFORE}"

# ============================================================
# 4. Launch Firefox to the admin panel
# ============================================================
echo "Launching Firefox to admin panel..."
pkill -9 -f firefox 2>/dev/null || true
for i in $(seq 1 20); do pgrep -f firefox > /dev/null 2>&1 || break; sleep 0.5; done
sleep 1
rm -f /home/ga/.mozilla/firefox/aerobridge.profile/lock \
       /home/ga/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock \
       /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock
su - ga -c "rm -f /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/.parentlock /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile/lock; DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox --new-instance \
    -profile /home/ga/snap/firefox/common/.mozilla/firefox/aerobridge.profile \
    'http://localhost:8000/admin/' &"
sleep 6

# ============================================================
# 5. Take initial screenshot to confirm setup
# ============================================================
echo "Taking initial screenshot..."
DISPLAY=:1 scrot /tmp/register_aircraft_start.png 2>/dev/null || true

echo "=== register_aircraft task setup complete ==="
echo "Task: Register aircraft 'Phoenix Mk3' (serial: PHX-MK3-2024-001, mark: VT-P001)"
echo "Admin URL: http://localhost:8000/admin/"
echo "Login: admin / adminpass123"
