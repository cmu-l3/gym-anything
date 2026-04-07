#!/bin/bash
set -e
echo "=== Setting up anonymize_dive_log task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Kill any existing Subsurface instances for a clean start
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf

# Populate all 8 dives with realistic Buddy and Divemaster names so there is data to scrub
python3 -c "
import xml.etree.ElementTree as ET

tree = ET.parse('/home/ga/Documents/dives.ssrf')
root = tree.getroot()

buddies = ['John Smith', 'Dr. Alice Waters', 'Michael Chen', 'Sarah Jenkins', 
           'David Patel', 'Emma Thompson', 'Robert Garcia', 'Lisa Wong']
divemasters = ['Capt. Ron', 'Divemaster Dan', 'Instructor Jane', 'Capt. Ron', 
               'Divemaster Dan', 'Instructor Jane', 'Capt. Ron', 'Divemaster Dan']

for i, dive in enumerate(root.iter('dive')):
    dive.set('buddy', buddies[i % len(buddies)])
    dive.set('divemaster', divemasters[i % len(divemasters)])

tree.write('/home/ga/Documents/dives.ssrf', xml_declaration=True, encoding='utf-8')
"

echo "Logbook pre-populated with realistic PII data for anonymization."

# Record initial state modification time for anti-gaming
stat -c%Y /home/ga/Documents/dives.ssrf > /tmp/ssrf_initial_mtime.txt

# Ensure X server access
xhost +local: 2>/dev/null || true

# Launch Subsurface with the sample data
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

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
sleep 4

# Dismiss any residual dialogs with Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize the Subsurface window
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="