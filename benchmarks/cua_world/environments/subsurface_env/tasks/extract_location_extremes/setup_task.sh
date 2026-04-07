#!/bin/bash
set -e
echo "=== Setting up extract_location_extremes task ==="

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

# Remove any pre-existing output file
rm -f /home/ga/Documents/sund_rock_records.txt 2>/dev/null || true

# Programmatically compute the ground truth for Sund Rock dives 
# and save it to a hidden location for the verifier to use.
cat << 'EOF' > /tmp/compute_gt.py
import xml.etree.ElementTree as ET
import json
import os

try:
    tree = ET.parse('/home/ga/Documents/dives.ssrf')
    root = tree.getroot()
    
    # Map divesite IDs to names
    site_map = {}
    for tag in ['site', 'divesite']:
        for site in root.iter(tag):
            uuid = site.get('uuid')
            name = site.get('name', '')
            if not name:
                name_elem = site.find('name')
                if name_elem is not None: name = name_elem.text
            if uuid: site_map[uuid] = name

    sund_rock_dives = []
    for dive in root.iter('dive'):
        # Resolve location
        loc_text = dive.get('location', '')
        site_ref = dive.get('divesiteid')
        if site_ref and site_ref in site_map:
            loc_text = site_map[site_ref]
        else:
            loc_elem = dive.find('location')
            if loc_elem is not None and loc_elem.text: loc_text = loc_elem.text

        if 'sund rock' in loc_text.lower():
            date = dive.get('date', '')
            
            # Resolve Depth
            depth = 0.0
            depth_elem = dive.find('depth')
            if depth_elem is not None:
                try: depth = float(depth_elem.get('max', '0').replace(' m', ''))
                except: pass
                
            # Resolve Duration
            dur_str = dive.get('duration', '0:0 min').replace(' min', '')
            parts = dur_str.split(':')
            try: dur_min = int(parts[0]) + (int(parts[1])/60.0 if len(parts)>1 else 0.0)
            except: dur_min = 0.0
            
            sund_rock_dives.append({'date': date, 'depth': depth, 'duration': dur_min})

    gt = {'error': 'No dives found'}
    if sund_rock_dives:
        deepest = max(sund_rock_dives, key=lambda x: x['depth'])
        longest = max(sund_rock_dives, key=lambda x: x['duration'])
        gt = {
            'deepest_date': deepest['date'],
            'deepest_val': deepest['depth'],
            'longest_date': longest['date'],
            'longest_val': longest['duration'],
            'count': len(sund_rock_dives)
        }
        
    with open('/tmp/sund_rock_gt.json', 'w') as f:
        json.dump(gt, f)
except Exception as e:
    with open('/tmp/sund_rock_gt.json', 'w') as f:
        json.dump({'error': str(e)}, f)
EOF
python3 /tmp/compute_gt.py
echo "Ground truth dynamically computed."

xhost +local: 2>/dev/null || true

# Launch Subsurface
echo "Launching Subsurface..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

# Wait for Subsurface window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
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

echo "=== Task setup complete ==="