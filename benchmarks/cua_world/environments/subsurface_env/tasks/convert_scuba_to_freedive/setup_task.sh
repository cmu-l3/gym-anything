#!/bin/bash
set -euo pipefail
echo "=== Setting up convert_scuba_to_freedive task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any existing Subsurface instances to ensure a clean start
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore fresh sample data
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf
echo "Clean sample data restored to /home/ga/Documents/dives.ssrf"

# Launch Subsurface
xhost +local: 2>/dev/null || true
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid subsurface /home/ga/Documents/dives.ssrf >/home/ga/subsurface_task.log 2>&1 &"

# Wait for Subsurface window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected."
        break
    fi
    sleep 1
done

# Allow time for UI to finish rendering
sleep 4

# Dismiss any residual startup dialogs with Escape, then maximize the window
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo ""
echo "Instructions:"
echo "1. Locate Dive #8 in the dive list (September 2011)."
echo "2. Edit the Location field to read 'Blue Hole'."
echo "3. Change the Dive Mode dropdown from Open Circuit to 'Freedive' or 'Apnea'."
echo "4. Save the logbook using Ctrl+S or the File menu."