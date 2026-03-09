#!/bin/bash
set -e
echo "=== Setting up create_dive_trip task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data
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
echo "TASK: Create a new dive trip and add a dive to it"
echo "============================================================"
echo ""
echo "Subsurface is open with the dive logbook."
echo ""
echo "Please:"
echo "1. Add a new dive (Log menu > Add Dive) with these details:"
echo "   - Date: September 10, 2022"
echo "   - Start time: 08:00"
echo "   - Duration: 55 minutes"
echo "   - Maximum depth: 28.0 meters"
echo "   - Buddy: Sara Al-Rashid"
echo "   - Notes: Night dive around the wreck of the SS Thistlegorm"
echo "2. Assign this dive to a trip named 'Red Sea Liveaboard 2022'"
echo "   with location 'Hurghada, Egypt'."
echo "   (You may need to create the trip via right-click > Create trip,"
echo "    or by using the trip header in the dive list.)"
echo "3. Save with Ctrl+S."
echo "============================================================"
