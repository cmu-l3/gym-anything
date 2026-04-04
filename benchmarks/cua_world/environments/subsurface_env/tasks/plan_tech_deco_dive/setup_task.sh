#!/bin/bash
set -e
echo "=== Setting up plan_tech_deco_dive task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time
date +%s > /tmp/plan_tech_deco_dive_start_ts

# Kill any existing Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf

# Record baseline: count of planned dives in the SSRF
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
tree = ET.parse('/home/ga/Documents/dives.ssrf')
root = tree.getroot()
planned_count = 0
for dive in root.iter('dive'):
    if 'plan' in dive.get('dive_mode', '').lower():
        planned_count += 1
with open('/tmp/plan_tech_deco_dive_initial_planned_count', 'w') as f:
    f.write(str(planned_count))
PYEOF

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
DISPLAY=:1 scrot /tmp/task_evidence/plan_tech_deco_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
