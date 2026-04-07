#!/bin/bash
echo "=== Setting up session_bus_routing task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_timestamp

# Kill any existing Ardour instances
kill_ardour

SESSION_DIR="/home/ga/Audio/sessions/MyProject"
SESSION_FILE="$SESSION_DIR/MyProject.ardour"
BACKUP_FILE="$SESSION_DIR/MyProject.ardour.clean_backup"

# Ensure session exists (create using environment setup logic if missing)
if [ ! -f "$SESSION_FILE" ]; then
    echo "Session file missing. Running default setup..."
    /workspace/scripts/setup_ardour.sh
fi

# Restore clean session to start fresh
if [ -f "$BACKUP_FILE" ]; then
    cp "$BACKUP_FILE" "$SESSION_FILE"
else
    cp "$SESSION_FILE" "$BACKUP_FILE"
fi

# Create routing spec document
cat > /home/ga/Audio/routing_spec.txt << 'SPEC'
=== MIXING SESSION ROUTING SPECIFICATION ===
Project: Local Band Demo
Engineer: Guest
Date: 2024-11-15

SUBMIX BUS STRUCTURE:
---------------------
1. "Drum Bus"    → receives: Kick, Snare, HiHat    → gain: -3 dB
2. "Music Bus"   → receives: Bass, Guitar          → gain: -2 dB
3. "Vocal Bus"   → receives: Vocals                → gain:  0 dB (unity)

All buses must output to the Master bus.

INSTRUCTIONS:
- Create 3 stereo audio buses with the exact names above
- Route each track's output to its assigned bus
- Set bus faders to the specified gain levels
- Save the session when complete
SPEC

chown ga:ga /home/ga/Audio/routing_spec.txt

# Inject the 6 required audio tracks via Python XML manipulation
# This duplicates the default 'Audio 1' track created by the env
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import sys, copy, os

session_file = '/home/ga/Audio/sessions/MyProject/MyProject.ardour'
if not os.path.exists(session_file):
    sys.exit(0)

tree = ET.parse(session_file)
root = tree.getroot()

# Find all audio routes that are not Master/Monitor
audio_routes = [r for r in root.iter('Route') 
                if r.get('default-type') == 'audio' 
                and 'MasterOut' not in r.get('flags', '') 
                and 'MonitorOut' not in r.get('flags', '')]

if not audio_routes:
    sys.exit(0)

base_route = audio_routes[0]
parent = {c: p for p in root.iter() for c in p}.get(base_route, root)

# Remove all existing standard audio tracks
for r in audio_routes:
    parent.remove(r)

track_names = ["Kick", "Snare", "HiHat", "Bass", "Guitar", "Vocals"]
base_id = 20000

# Get PresentationInfo to register routes in GUI
pi = root.find('PresentationInfo')
rd_base = None
if pi is not None:
    for rd in pi.findall('RouteDisplay'):
        if rd.get('route-id') == base_route.get('id'):
            rd_base = rd
            pi.remove(rd)
            break

for i, name in enumerate(track_names):
    new_route = copy.deepcopy(base_route)
    new_route.set('name', name)
    new_route_id = str(base_id + i*100)
    new_route.set('id', new_route_id)
    
    for io in new_route.findall('IO'):
        io.set('name', name)
        io.set('id', str(base_id + i*100 + 1))
        for port in io.findall('Port'):
            old_pname = port.get('name', '')
            if '/' in old_pname:
                port.set('name', name + '/' + old_pname.split('/')[1])
    parent.append(new_route)
    
    if pi is not None and rd_base is not None:
        new_rd = copy.deepcopy(rd_base)
        new_rd.set('route-id', new_route_id)
        pi.append(new_rd)

tree.write(session_file, xml_declaration=True, encoding='UTF-8')
PYEOF

# Record baseline counts for verification
INITIAL_TRACK_COUNT=$(grep -c '<Route.*default-type="audio"' "$SESSION_FILE" 2>/dev/null || echo "0")
echo "$INITIAL_TRACK_COUNT" > /tmp/initial_track_count
stat -c %Y "$SESSION_FILE" > /tmp/initial_session_mtime

# Launch Ardour
launch_ardour_session "$SESSION_FILE"

sleep 5

# Ensure Mixer window is accessible (shortcut Alt+M toggles it)
# We don't force it open, let the agent figure it out, but ensure main window focus
WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="