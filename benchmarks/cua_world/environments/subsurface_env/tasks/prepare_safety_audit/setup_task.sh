#!/bin/bash
set -e
echo "=== Setting up prepare_safety_audit task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Kill any existing Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf

# Ensure units are set to metric (the task requires switching to imperial)
# The default config already has metric units, but ensure it explicitly
python3 << 'PYEOF'
import configparser
import os

conf_path = '/home/ga/.config/Subsurface/Subsurface.conf'
# Read current config
with open(conf_path) as f:
    content = f.read()

# Make sure unit_system is NOT set to imperial
if 'unit_system=1' in content:
    content = content.replace('unit_system=1', 'unit_system=0')
    with open(conf_path, 'w') as f:
        f.write(content)
PYEOF

# Remove any existing buddy from Dive #3 (Dec 4, 2010 second dive)
# to create a "missing buddy" condition for the task
python3 << 'PYEOF'
import xml.etree.ElementTree as ET

tree = ET.parse('/home/ga/Documents/dives.ssrf')
root = tree.getroot()

for dive in root.iter('dive'):
    num = dive.get('number', '')
    # Remove buddy from Dive #3 and #5 to create missing buddy scenario
    if num in ('3', '5'):
        if 'buddy' in dive.attrib:
            del dive.attrib['buddy']
        # Also remove buddy child element if present
        buddy_elem = dive.find('buddy')
        if buddy_elem is not None:
            dive.remove(buddy_elem)

tree.write('/home/ga/Documents/dives.ssrf', xml_declaration=True, encoding='utf-8')
PYEOF

chown ga:ga /home/ga/Documents/dives.ssrf

# Delete any stale export files
rm -f /home/ga/Documents/safety_audit_export.csv 2>/dev/null || true

# Record task start time AFTER cleanup
date +%s > /tmp/prepare_safety_audit_start_ts

# Record baseline SSRF mtime
stat -c%Y /home/ga/Documents/dives.ssrf > /tmp/prepare_safety_audit_initial_mtime

# Record which dives are deeper than 18m (for verifier reference)
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import re

tree = ET.parse('/home/ga/Documents/dives.ssrf')
root = tree.getroot()

deep_dives = []
for dive in root.iter('dive'):
    depth_str = dive.get('depth', '')
    try:
        depth_val = float(re.sub(r'[^0-9.]', '', depth_str))
        if depth_val > 18:
            deep_dives.append(dive.get('number', '?'))
    except (ValueError, AttributeError):
        pass

with open('/tmp/prepare_safety_audit_deep_dives', 'w') as f:
    f.write(','.join(deep_dives))
PYEOF

xhost +local: 2>/dev/null || true

# Launch Subsurface
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf \
    >/home/ga/subsurface_task.log 2>&1 &"
sleep 3

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        break
    fi
    sleep 2
done
sleep 5

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize window
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take screenshot
mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_evidence/prepare_safety_audit_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
