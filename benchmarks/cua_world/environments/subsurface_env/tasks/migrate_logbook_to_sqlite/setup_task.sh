#!/bin/bash
set -e
echo "=== Setting up migrate_logbook_to_sqlite task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Kill any existing Subsurface instances for a clean start
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# 3. Restore clean sample data and clear any previous outputs
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf

# Remove the target db file if it already exists from a previous run
rm -f /home/ga/Documents/dives.db 2>/dev/null || true

# Record initial state of the source file
SSRF_INITIAL_MTIME=$(stat -c%Y /home/ga/Documents/dives.ssrf)
echo "$SSRF_INITIAL_MTIME" > /tmp/ssrf_initial_mtime.txt

# Ensure X server access
xhost +local: 2>/dev/null || true

# 4. Launch Subsurface with the sample XML data
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"

# Wait for Subsurface window to appear
echo "Waiting for Subsurface window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected."
        break
    fi
    sleep 1
done

# Additional wait for full UI initialization
sleep 3

# Dismiss any residual startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 0.5
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_evidence/initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="