#!/bin/bash
set -e
echo "=== Setting up fix_location_data task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time
date +%s > /tmp/fix_location_data_start_ts

# Kill any existing Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# Restore clean sample data
cp /opt/subsurface_data/SampleDivesV2.ssrf /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf

# Inject location data errors into the dive sites
python3 << 'PYEOF'
import xml.etree.ElementTree as ET

tree = ET.parse('/home/ga/Documents/dives.ssrf')
root = tree.getroot()

# Find divesites section
divesites = root.find('divesites')
if divesites is not None:
    for site in divesites.findall('site'):
        name = site.get('name', '')

        # Error 1: Corrupt Sund Rock GPS to Null Island (0,0)
        # Also garble the name to "Snd Rck"
        if 'Sund Rock' in name:
            site.set('gps', '0.0 0.0')
            site.set('name', 'Snd Rck')

        # Error 2: Corrupt Yellow House GPS to inland California
        elif 'Yellow House' in name:
            site.set('gps', '35.0 -120.0')

# Also corrupt any location elements directly in dives
for dive in root.iter('dive'):
    loc = dive.find('location')
    if loc is not None:
        loc_text = loc.text or ''
        gps = loc.get('gps', '')

        if 'Sund Rock' in loc_text:
            loc.text = 'Snd Rck'
            if gps:
                loc.set('gps', '0.0 0.0')

        elif 'Yellow House' in loc_text:
            if gps:
                loc.set('gps', '35.0 -120.0')

tree.write('/home/ga/Documents/dives.ssrf', xml_declaration=True, encoding='utf-8')
PYEOF

chown ga:ga /home/ga/Documents/dives.ssrf

# Record baseline SSRF mtime
stat -c%Y /home/ga/Documents/dives.ssrf > /tmp/fix_location_data_initial_mtime

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
DISPLAY=:1 scrot /tmp/task_evidence/fix_location_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
