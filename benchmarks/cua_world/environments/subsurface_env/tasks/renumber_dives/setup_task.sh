#!/bin/bash
set -euo pipefail

echo "=== Setting up renumber_dives task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time (for anti-gaming checks)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time.txt

# Kill any existing Subsurface instances for a clean start
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean, real sample data from the official repo
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf

# Extract initial state to JSON using Python to avoid brittle XML grepping
INITIAL_MTIME=$(stat -c%Y /home/ga/Documents/dives.ssrf)
python3 -c "
import xml.etree.ElementTree as ET
import json
try:
    tree = ET.parse('/home/ga/Documents/dives.ssrf')
    dives = tree.findall('.//dive')
    count = len(dives)
    
    with open('/tmp/initial_state.json', 'w') as f:
        json.dump({
            'count': count, 
            'mtime': $INITIAL_MTIME, 
            'start_time': $TASK_START
        }, f)
except Exception as e:
    print('Error parsing XML:', e)
"

xhost +local: 2>/dev/null || true

# Launch Subsurface and load the log
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"

# Wait for Subsurface window to appear
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected at iteration $i"
        break
    fi
    sleep 1
done
sleep 3

# Dismiss any startup dialogs (like update checkers)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize the Subsurface window and focus it
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take initial screenshot for visual evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="