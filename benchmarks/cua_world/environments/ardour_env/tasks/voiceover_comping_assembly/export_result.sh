#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Voiceover Comping Assembly Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    kill_ardour
fi

sleep 1

# Extract deep properties directly from the session XML to assess exact edits
cat > /tmp/parse_ardour.py << 'EOF'
import xml.etree.ElementTree as ET
import json
import os
import time

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

if not os.path.exists(SESSION_FILE):
    print(json.dumps({'session_exists': False}))
    exit(0)

try:
    tree = ET.parse(SESSION_FILE)
    root = tree.getroot()
except Exception as e:
    print(json.dumps({'session_exists': False, 'error': str(e)}))
    exit(0)

sources = {s.get('id'): s.get('name', '') for s in root.findall('.//Source')}
regions = {r.get('id'): r for r in root.findall('.//Region')}

# Function to recursively trace sub-regions back to the original source file and compute true time offset
def trace_region(region_node):
    total_start = 0
    curr_node = region_node
    
    for _ in range(20):
        total_start += int(curr_node.get('start', '0'))
        src_id = curr_node.get('source-0')
        
        if src_id in sources:
            return sources[src_id], total_start
            
        if src_id in regions:
            curr_node = regions[src_id]
        else:
            return "unknown", total_start
    return "unknown", total_start

routes_info = []
for route in root.findall('.//Route'):
    flags = route.get('flags', '')
    if 'MasterOut' in flags or 'MonitorOut' in flags:
        continue
    if route.get('default-type') != 'audio':
        continue
        
    route_name = route.get('name', '')
    
    muted = route.get('muted', '0') in ('1', 'yes', 'true')
    for ctrl in route.findall('.//Controllable'):
        if ctrl.get('name') == 'mute' and ctrl.get('value', '0') in ('1', 'yes', 'true'):
            muted = True
            
    route_regions = []
    diskstream = route.find('Diskstream')
    if diskstream is not None:
        playlist_name = diskstream.get('playlist', '')
        for playlist in root.findall('.//Playlist'):
            if playlist.get('name') == playlist_name:
                for region in playlist.findall('Region'):
                    source_name, true_start = trace_region(region)
                    route_regions.append({
                        'name': region.get('name', ''),
                        'true_start': true_start,
                        'length': int(region.get('length', '0')),
                        'position': int(region.get('position', '0')),
                        'source_file': source_name
                    })
    
    # Sort regions by position on the timeline
    route_regions.sort(key=lambda x: x['position'])
    
    routes_info.append({
        'name': route_name,
        'muted': muted,
        'regions': route_regions
    })

task_start = 0
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        task_start = int(f.read().strip())
except:
    pass

print(json.dumps({
    'session_exists': True,
    'routes': routes_info,
    'task_start_timestamp': task_start,
    'export_timestamp': int(time.time())
}))
EOF

python3 /tmp/parse_ardour.py > /tmp/vo_comping_result.json

echo "Result saved to /tmp/vo_comping_result.json"
echo "=== Export Complete ==="