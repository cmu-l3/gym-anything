#!/bin/bash
set -e
echo "=== Setting up edit_dive_site_gps task ==="

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

# Use python to strip GPS from the target dive site to create the missing GPS scenario
python3 << 'EOF'
import xml.etree.ElementTree as ET
import os

ssrf_path = '/home/ga/Documents/dives.ssrf'
tree = ET.parse(ssrf_path)
root = tree.getroot()
removed = False
initial_gps_count = 0

# Try to remove GPS from "Sund Rock" or "Great Wall" site specifically
for site in root.iter('site'):
    if 'gps' in site.attrib:
        name = site.get('name', '')
        if not removed and ('Sund Rock' in name or 'Great Wall' in name or 'Yellow House' in name):
            del site.attrib['gps']
            removed = True
        else:
            initial_gps_count += 1

# Fallback if specific names weren't found: remove the first GPS found
if not removed:
    for site in root.iter('site'):
        if 'gps' in site.attrib:
            del site.attrib['gps']
            removed = True
            break
            
# Recount to be absolutely sure
initial_gps_count = sum(1 for s in root.iter('site') if 'gps' in s.attrib)

tree.write(ssrf_path)
with open('/tmp/initial_gps_count.txt', 'w') as f:
    f.write(str(initial_gps_count))
EOF

echo "Clean sample data restored and target GPS coordinates stripped."

# Record initial file modification time for anti-gaming
stat -c%Y /home/ga/Documents/dives.ssrf > /tmp/ssrf_initial_mtime.txt

# Ensure X server access
xhost +local: 2>/dev/null || true

# Launch Subsurface with the prepared data
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

# Maximize the Subsurface window
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_evidence/initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_evidence/initial_state.png 2>/dev/null || true

echo ""
echo "=== Task setup complete ==="