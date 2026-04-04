#!/bin/bash
set -e
echo "=== Setting up plan_basic_dive task ==="

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
echo "TASK: Plan a basic recreational dive using the Dive Planner"
echo "============================================================"
echo ""
echo "Subsurface is open."
echo ""
echo "Please:"
echo "1. Open the Dive Planner."
echo "   Look for a 'Plan Dive' button or tab at the bottom of the"
echo "   dive profile area, OR use the Planner menu at the top."
echo "2. Set up the dive plan with these parameters:"
echo "   - Bottom depth: 30 meters"
echo "   - Bottom time: 40 minutes"
echo "   - Gas: Air (21% O2, 0% He)"
echo "   - SAC: 20 liters/min (if prompted)"
echo "3. Review the dive plan profile shown."
echo "4. Click 'Remember dive plan' or equivalent to save the planned"
echo "   dive to your logbook."
echo "5. Save the logbook (Ctrl+S)."
echo "============================================================"
