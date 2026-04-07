#!/bin/bash
set -euo pipefail

echo "=== Setting up Set Dive Rating and Visibility task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Kill any existing Subsurface instances for clean start
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data (task starts fresh every time)
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf
echo "Clean sample data restored: $(stat -c%s /home/ga/Documents/dives.ssrf) bytes"

# Remove any previous task output or backup files
rm -f /home/ga/Documents/dives.ssrf.bak 2>/dev/null || true

# Record initial state for anti-gaming (hash and mtime)
md5sum /home/ga/Documents/dives.ssrf | awk '{print $1}' > /tmp/initial_file_hash.txt
stat -c%Y /home/ga/Documents/dives.ssrf > /tmp/initial_mtime.txt

# Ensure X server access
xhost +local: 2>/dev/null || true

# Launch Subsurface with the sample data
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 4

# Wait for Subsurface window to appear (up to 30s)
echo "Waiting for Subsurface window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected at iteration $i"
        break
    fi
    sleep 1
done

# Additional wait for full UI initialization
sleep 3

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
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Set rating and visibility for Dive #2"
echo "============================================================"
echo "Subsurface is open with the dive logbook (8 dives)."
echo "Select Dive #2, set Rating to 4 stars, set Visibility to 3 stars."
echo "Save the logbook when done (Ctrl+S)."
echo "============================================================"