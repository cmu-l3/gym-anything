#!/bin/bash
set -e
echo "=== Setting up audit_fix_gas_configs task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time
date +%s > /tmp/audit_fix_gas_configs_start_ts

# Kill any existing Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf

# Inject gas configuration errors into the September 2011 trip dives
# These are real dives from the official Subsurface sample data
python3 << 'PYEOF'
import xml.etree.ElementTree as ET

tree = ET.parse('/home/ga/Documents/dives.ssrf')
root = tree.getroot()

for dive in root.iter('dive'):
    num = dive.get('number', '')

    # Error 1: Dive #85 - Set O2 to 50% (unsafe for recorded depth ~27m)
    # At 1.4 ppO2, MOD for 50% is only ~18m. This dive went to ~27m.
    if num == '85':
        for cyl in dive.findall('cylinder'):
            cyl.set('o2', '50.0%')

    # Error 2: Dive #86 - Set cylinder size to 3.0L (impossibly small)
    # A 3L pony bottle cannot sustain a 40+ minute dive at depth
    elif num == '86':
        for cyl in dive.findall('cylinder'):
            cyl.set('size', '3.0 l')

    # Error 3: Dive #87 - Set working pressure to 50 bar (far too low)
    # Standard scuba cylinders are rated 200-300 bar
    elif num == '87':
        for cyl in dive.findall('cylinder'):
            cyl.set('workpressure', '50.0 bar')

tree.write('/home/ga/Documents/dives.ssrf', xml_declaration=True, encoding='utf-8')
PYEOF

chown ga:ga /home/ga/Documents/dives.ssrf

# Record baseline SSRF mtime
stat -c%Y /home/ga/Documents/dives.ssrf > /tmp/audit_fix_gas_configs_initial_mtime

xhost +local: 2>/dev/null || true

# Launch Subsurface
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        break
    fi
    sleep 2
done
sleep 5

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize window
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take screenshot
mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_evidence/audit_fix_gas_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
