#!/bin/bash
set -e
echo "=== Setting up update_dive_notes task ==="

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
echo "TASK: Update notes for Dive #4"
echo "============================================================"
echo ""
echo "Subsurface is open."
echo ""
echo "Please:"
echo "1. Find Dive #4 (December 5, 2010, first dive of that day"
echo "   at Sund Rock). It is in the December 2010 trip."
echo "2. Click on that dive to select it."
echo "3. In the dive details panel (About This Dive / Notes tab),"
echo "   find the 'Notes' text field."
echo "4. Replace any existing notes with:"
echo "   'Spotted a giant Pacific octopus near the rocky outcrop at"
echo "   10 meters depth. Visibility approximately 8 meters. Water"
echo "   temperature was cold at 8 degrees Celsius.'"
echo "5. Save with Ctrl+S."
echo "============================================================"
