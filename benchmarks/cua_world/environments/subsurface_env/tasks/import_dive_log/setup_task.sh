#!/bin/bash
set -e
echo "=== Setting up import_dive_log task ==="

export DISPLAY="${DISPLAY:-:1}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/gdm/Xauthority}"

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
sleep 1

# Kill any existing Subsurface instances for a clean start
pkill -9 -f subsurface 2>/dev/null || true
sleep 3

# =====================================================================
# Split the official sample dive data into two files by trip
# =====================================================================
echo "Splitting sample data into two realistic log files..."

python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import copy
import hashlib
import os

source = '/opt/subsurface_data/SampleDivesV2.ssrf'
main_out = '/home/ga/Documents/dives.ssrf'
import_out = '/home/ga/Documents/import_dives.ssrf'

tree = ET.parse(source)
root = tree.getroot()

# Locate the container for trips and dives
dives_elem = root.find('dives')
if dives_elem is None:
    for child in root:
        if 'dives' in child.tag.lower():
            dives_elem = child
            break
if dives_elem is None:
    dives_elem = root

trips = list(dives_elem.findall('trip'))
standalone_dives = list(dives_elem.findall('dive'))

# Duplicate roots for the two files
main_root = copy.deepcopy(root)
main_dives = main_root.find('dives')
if main_dives is None:
    for child in main_root:
        if 'dives' in child.tag.lower():
            main_dives = child
            break
if main_dives is None:
    main_dives = main_root

import_root = copy.deepcopy(root)
import_dives = import_root.find('dives')
if import_dives is None:
    for child in import_root:
        if 'dives' in child.tag.lower():
            import_dives = child
            break
if import_dives is None:
    import_dives = import_root

# Clear existing elements to rebuild them
for elem in list(main_dives):
    if elem.tag in ['trip', 'dive']:
        main_dives.remove(elem)

for elem in list(import_dives):
    if elem.tag in ['trip', 'dive']:
        import_dives.remove(elem)

# Split: Main gets all but the last trip; Import gets only the last trip
if len(trips) >= 2:
    for trip in trips[:-1]:
        main_dives.append(trip)
    for d in standalone_dives:
        main_dives.append(d)
        
    import_dives.append(trips[-1])
else:
    # Fallback if fewer than 2 trips
    mid = len(standalone_dives) // 2
    for d in standalone_dives[:mid]:
        main_dives.append(d)
    for d in standalone_dives[mid:]:
        import_dives.append(d)

# Write the split files
ET.ElementTree(main_root).write(main_out, xml_declaration=True, encoding='utf-8')
ET.ElementTree(import_root).write(import_out, xml_declaration=True, encoding='utf-8')

# Calculate initial state hash and dive counts
with open(main_out, 'rb') as f:
    main_hash = hashlib.md5(f.read()).hexdigest()

main_dive_count = sum(1 for _ in main_root.iter('dive'))
import_dive_count = sum(1 for _ in import_root.iter('dive'))
total_dive_count = main_dive_count + import_dive_count

# Save initial state variables
with open('/tmp/initial_dive_count.txt', 'w') as f: f.write(str(main_dive_count))
with open('/tmp/import_dive_count.txt', 'w') as f: f.write(str(import_dive_count))
with open('/tmp/total_dive_count.txt', 'w') as f: f.write(str(total_dive_count))
with open('/tmp/initial_file_hash.txt', 'w') as f: f.write(main_hash)

print(f"Main file created with {main_dive_count} dives.")
print(f"Import file created with {import_dive_count} dives.")
print(f"Expected total after merge: {total_dive_count} dives.")
PYEOF

# Set appropriate permissions
chown ga:ga /home/ga/Documents/dives.ssrf
chown ga:ga /home/ga/Documents/import_dives.ssrf
chmod 644 /home/ga/Documents/dives.ssrf
chmod 644 /home/ga/Documents/import_dives.ssrf

# =====================================================================
# Launch Subsurface with the partial (main) dive log
# =====================================================================
echo "Launching Subsurface with partial dive log..."
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid subsurface /home/ga/Documents/dives.ssrf >/home/ga/subsurface_task.log 2>&1 &"

# Wait for Subsurface window to appear
echo "Waiting for Subsurface window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected (attempt $i)"
        break
    fi
    sleep 2
done
sleep 5

# Dismiss any potential startup dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize and focus the application
DISPLAY=:1 wmctrl -r "Subsurface" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Subsurface" 2>/dev/null || true
sleep 1

# Take an initial screenshot to provide task setup evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="