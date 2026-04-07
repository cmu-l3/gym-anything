#!/bin/bash
set -e
echo "=== Setting up plan_tech_training_series task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

TASK_NAME="plan_tech_training_series"

# Kill any existing Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Clean up any stale output files BEFORE recording timestamps
rm -f /home/ga/Documents/tech_training_plan.pdf 2>/dev/null || true

# Record task start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Restore clean sample data
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf

# Record baseline dive count and file state
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
tree = ET.parse('/home/ga/Documents/dives.ssrf')
root = tree.getroot()
dive_count = sum(1 for _ in root.iter('dive'))
with open('/tmp/plan_tech_training_series_initial_dive_count', 'w') as f:
    f.write(str(dive_count))
PYEOF

stat -c%Y /home/ga/Documents/dives.ssrf > /tmp/${TASK_NAME}_initial_mtime

# Ensure output directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Create task evidence directory
mkdir -p /tmp/task_evidence

xhost +local: 2>/dev/null || true

# Launch Subsurface as user ga
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

# Wait for Subsurface window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        break
    fi
    sleep 2
done
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize window
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_evidence/${TASK_NAME}_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
