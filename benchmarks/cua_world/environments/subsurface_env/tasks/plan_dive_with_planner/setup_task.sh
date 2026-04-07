#!/bin/bash
set -e
echo "=== Setting up plan_dive_with_planner task ==="

export DISPLAY="${DISPLAY:-:1}"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf
echo "Clean sample data restored to /home/ga/Documents/dives.ssrf"

# Record initial dive count using Python to parse XML safely
INITIAL_COUNT=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('/home/ga/Documents/dives.ssrf')
    print(len(tree.getroot().findall('.//dive')))
except Exception:
    print("0")
PYEOF
)
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial dive count recorded: $INITIAL_COUNT"

# Ensure X server is accessible
xhost +local: 2>/dev/null || true

# Launch Subsurface
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 setsid subsurface /home/ga/Documents/dives.ssrf >/tmp/subsurface_task.log 2>&1 &"

# Wait for Subsurface window to appear
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected at iteration $i"
        break
    fi
    sleep 1
done

# Additional wait for full UI initialization
sleep 4

# Maximize the Subsurface window
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="