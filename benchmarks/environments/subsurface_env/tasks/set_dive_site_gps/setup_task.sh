#!/bin/bash
set -e
echo "=== Setting up set_dive_site_gps task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data
# Note: Dive #2 in the sample data may or may not have GPS coordinates.
# The task asks the agent to set specific GPS coords.
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf
echo "Clean sample data restored."

stat -c%Y /home/ga/Documents/dives.ssrf > /tmp/ssrf_initial_mtime.txt

xhost +local: 2>/dev/null || true

echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected at iteration $i"
        break
    fi
    sleep 2
done
sleep 5

DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_evidence/initial_state.png 2>/dev/null || true

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Set GPS coordinates for Dive #2's dive site"
echo "============================================================"
echo ""
echo "Subsurface is open."
echo ""
echo "Please:"
echo "1. Find Dive #2 (December 4, 2010, Sund Rock, first dive)"
echo "   in the December 2010 trip."
echo "2. Click on that dive to select it."
echo "3. In the dive details panel, find the location/GPS field."
echo "   Look for the 'Location' field in the About This Dive tab."
echo "4. Enter GPS coordinates: 47.4005 -123.1420"
echo "   (latitude 47.4005 N, longitude 123.1420 W)"
echo "5. Save with Ctrl+S."
echo "============================================================"
