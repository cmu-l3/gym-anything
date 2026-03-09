#!/bin/bash
# setup_task.sh — pre_task hook for add_pilot
# Removes any pre-existing test pilot, records baseline, launches Firefox

echo "=== Setting up add_pilot task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for server
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# Remove pre-existing test person if any
echo "Removing any pre-existing 'Aditya Kumar' person records..."
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
    from registry.models import Person
    deleted, _ = Person.objects.filter(
        first_name='Aditya', last_name='Kumar'
    ).delete()
    if deleted:
        print(f"Removed {deleted} existing 'Aditya Kumar' person record(s)")
    else:
        print("No pre-existing 'Aditya Kumar' found (clean)")
    print(f"Current person count: {Person.objects.count()}")
except Exception as e:
    print(f"Cleanup note: {e}")
PYEOF

# Record task start
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time

PERSON_COUNT_BEFORE=$(/opt/aerobridge_venv/bin/python3 -c "
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
from registry.models import Person
print(Person.objects.count())
" 2>/dev/null || echo "0")
echo "$PERSON_COUNT_BEFORE" > /tmp/person_count_before
echo "Person count before task: ${PERSON_COUNT_BEFORE}"

# Register Person model in Django admin (needed for '+' popup button on Pilot form)
echo "Registering Person model in Django admin..."
/opt/aerobridge_venv/bin/python3 - << 'PYEOF'
admin_file = '/opt/aerobridge/registry/admin.py'
with open(admin_file, 'r') as f:
    content = f.read()
if 'admin.site.register(Person)' not in content:
    # Try exact import line replacement first
    patched = content.replace(
        'from .models import AircraftMasterComponent, AircraftModel, Authorization, Activity, Company, ManufacturerPart, Operator, Contact, Aircraft, Pilot, AircraftDetail, AircraftComponent, Firmware, AircraftAssembly, SupplierPart, MasterComponentAssembly',
        'from .models import AircraftMasterComponent, AircraftModel, Authorization, Activity, Company, ManufacturerPart, Operator, Contact, Aircraft, Person, Pilot, AircraftDetail, AircraftComponent, Firmware, AircraftAssembly, SupplierPart, MasterComponentAssembly'
    )
    # Fall back: inject Person import before Pilot import if exact line didn't match
    if 'Person' not in patched:
        import re
        patched = re.sub(r'(from \.models import[^\n]*)', r'\1\nfrom registry.models import Person', patched, count=1)
    patched = patched.replace(
        'admin.site.register(Pilot)',
        'admin.site.register(Person)\nadmin.site.register(Pilot)'
    )
    with open(admin_file, 'w') as f:
        f.write(patched)
    # Verify the patch actually worked
    with open(admin_file, 'r') as f:
        verify = f.read()
    if 'admin.site.register(Person)' in verify:
        print('SUCCESS: Patched registry/admin.py to register Person model')
    else:
        print('WARNING: admin.py patch may have failed — Person not found in file after patching')
        print('Attempting fallback: appending registration to admin.py')
        with open(admin_file, 'a') as f:
            f.write('\nfrom registry.models import Person\nadmin.site.register(Person)\n')
        print('Fallback applied')
else:
    print('Person already registered in admin.py')
PYEOF
# Wait for Django runserver to auto-reload (poll instead of blind sleep)
for i in $(seq 1 10); do sleep 1; done

# Launch Firefox
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
    'http://localhost:8000/admin/registry/pilot/add/' &"
sleep 6

# Take initial screenshot
DISPLAY=:1 scrot /tmp/add_pilot_start.png 2>/dev/null || true

echo "=== add_pilot task setup complete ==="
echo "Task: Add person 'Aditya Kumar' (aditya.kumar@droneops.in)"
echo "Admin URL: http://localhost:8000/admin/"
echo "Login: admin / adminpass123"
