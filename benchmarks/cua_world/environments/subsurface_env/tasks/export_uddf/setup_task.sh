#!/bin/bash
set -e
echo "=== Setting up export_uddf task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure clean state: Remove any pre-existing output file
rm -f /home/ga/Documents/*.uddf 2>/dev/null || true

# Kill any existing Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data
if [ -f /opt/subsurface_data/SampleDivesV2.ssrf ]; then
    cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
    chown ga:ga /home/ga/Documents/dives.ssrf
    chmod 644 /home/ga/Documents/dives.ssrf
    echo "Clean sample data restored: $(stat -c%s /home/ga/Documents/dives.ssrf) bytes"
else
    echo "WARNING: Original sample data not found at /opt/subsurface_data/SampleDivesV2.ssrf"
fi

xhost +local: 2>/dev/null || true

# Launch Subsurface with the sample data
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

# Wait for Subsurface window to appear
echo "Waiting for Subsurface window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected at iteration $i"
        break
    fi
    sleep 2
done

# Additional wait for full UI initialization
sleep 5

# Dismiss any residual dialogs with Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize the Subsurface window
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Export Dive Log to UDDF"
echo "============================================================"
echo "Subsurface is open with the official sample dive logbook loaded."
echo ""
echo "Please export all dives to:"
echo "  /home/ga/Documents/exported_dives.uddf"
echo ""
echo "Format must be: UDDF (Universal Dive Data Format)"
echo "Make sure to export all dives (the file contains 8 dives across 2 trips)."
echo "============================================================"