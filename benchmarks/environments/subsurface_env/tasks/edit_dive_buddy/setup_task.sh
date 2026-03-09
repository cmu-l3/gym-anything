#!/bin/bash
set -e
echo "=== Setting up edit_dive_buddy task ==="

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
echo "Clean sample data restored: $(stat -c%s /home/ga/Documents/dives.ssrf) bytes"

# Record initial state
stat -c%Y /home/ga/Documents/dives.ssrf > /tmp/ssrf_initial_mtime.txt

# Verify the target dive exists in the data
if ! grep -q 'number="2"' /home/ga/Documents/dives.ssrf 2>/dev/null; then
    echo "WARNING: Dive #2 not found in sample data — check data integrity"
fi

xhost +local: 2>/dev/null || true

# Launch Subsurface
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected at iteration $i"
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
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take screenshot
mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_evidence/initial_state.png 2>/dev/null || true

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Edit the buddy field for Dive #2"
echo "============================================================"
echo ""
echo "Subsurface is open. The dive list shows 29 dives across 6 trips."
echo ""
echo "Please:"
echo "1. Find Dive #2 (December 4, 2010, Sund Rock, first dive of that trip)"
echo "   It is listed under the 'Hoodsport, WA, USA' trip from December 2010."
echo "2. Click on that dive to select it."
echo "3. In the dive details panel (right side), find the 'Buddy' field."
echo "4. Set the buddy to: Michael Chen"
echo "5. Save with Ctrl+S."
echo "============================================================"
