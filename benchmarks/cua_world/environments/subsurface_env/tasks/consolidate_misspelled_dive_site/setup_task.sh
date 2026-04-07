#!/bin/bash
set -e
echo "=== Setting up consolidate_misspelled_dive_site task ==="

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

# Use a Python script to deterministically inject the "Yelow House" typo scenario
# This separates one dive into a duplicate site entity to test relational consolidation
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import random

try:
    tree = ET.parse('/home/ga/Documents/dives.ssrf')
    root = tree.getroot()

    # Find the original "Yellow House" site
    yh_site = None
    for site in root.iter('site'):
        if site.get('name') == 'Yellow House':
            yh_site = site
            break

    if yh_site is not None:
        yh_uuid = yh_site.get('uuid')
        # Generate a random 8-character hex UUID for the typo site
        typo_uuid = f"{random.randint(0, 0xffffffff):08x}"
        
        # Create the duplicate typo site
        typo_site = ET.Element('site', {'uuid': typo_uuid, 'name': 'Yelow House'})
        
        # Copy relevant child elements (like GPS) to make it look legitimate
        for child in yh_site:
            typo_site.append(child)
            
        # Append to the same parent
        for parent in root.iter():
            if yh_site in list(parent):
                parent.append(typo_site)
                break
                
        # Reassign exactly ONE dive to this typo site
        for dive in root.iter('dive'):
            if dive.get('siteid') == yh_uuid:
                dive.set('siteid', typo_uuid)
                break  # Only change the first one we find
                
        tree.write('/home/ga/Documents/dives.ssrf')
        print("Successfully injected 'Yelow House' typo site.")
    else:
        print("Warning: 'Yellow House' not found in sample data.")
except Exception as e:
    print(f"Error during typo injection: {e}")
PYEOF

# Record initial state
SSRF_INITIAL_MTIME=$(stat -c%Y /home/ga/Documents/dives.ssrf)
echo "$SSRF_INITIAL_MTIME" > /tmp/ssrf_initial_mtime.txt
echo "Sample data prepared: $(stat -c%s /home/ga/Documents/dives.ssrf) bytes"

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
        echo "Subsurface window detected"
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
DISPLAY=:1 scrot /tmp/task_evidence/initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_evidence/initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="