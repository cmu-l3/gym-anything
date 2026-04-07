#!/bin/bash
set -e
echo "=== Setting up rename_dive_computer task ==="

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

# Ensure a clean slate by stripping any existing nicknames (in case sample data changed)
sed -i 's/nickname="[^"]*"//g' /home/ga/Documents/dives.ssrf
sed -i "s/nickname='[^']*'//g" /home/ga/Documents/dives.ssrf

echo "Clean sample data restored."

# Record initial file modification time and hash
stat -c%Y /home/ga/Documents/dives.ssrf > /tmp/ssrf_initial_mtime.txt
sha256sum /home/ga/Documents/dives.ssrf | awk '{print $1}' > /tmp/ssrf_initial_hash.txt

xhost +local: 2>/dev/null || true

# Launch Subsurface
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

# Wait for the application window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected at iteration $i"
        break
    fi
    sleep 2
done
sleep 5

# Clear any popups and ensure the window is maximized and focused
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take an initial screenshot for evidence
mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_evidence/initial_state.png 2>/dev/null || true

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Rename the 'OSTC 3' dive computer to 'Primary OSTC'"
echo "============================================================"
echo ""
echo "Subsurface is open."
echo ""
echo "Please:"
echo "1. Go to Log > Edit device names (or Manage dive computers) in the menu."
echo "2. Find the 'OSTC 3' device in the list."
echo "3. Change its Nickname to 'Primary OSTC'."
echo "4. Close the dialog."
echo "5. Save the logbook using Ctrl+S or File > Save."
echo "============================================================"