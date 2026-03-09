#!/bin/bash
set -e
echo "=== Setting up export_dives_csv task ==="

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

# Remove any existing output file from prior runs
rm -f /home/ga/Documents/dive_log.csv 2>/dev/null || true

# Record initial state for anti-gaming
stat -c%Y /home/ga/Documents/dives.ssrf > /tmp/ssrf_initial_mtime.txt
echo "false" > /tmp/csv_existed_before.txt

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
echo "TASK: Export all dives to CSV"
echo "============================================================"
echo ""
echo "Subsurface is open with 29 dives loaded (across 6 trips)."
echo ""
echo "Please:"
echo "1. Go to File menu > Export (or press Ctrl+E)."
echo "3. Choose CSV export format."
echo "4. Save the file to: /home/ga/Documents/dive_log.csv"
echo "============================================================"
