#!/bin/bash
set -e
echo "=== Setting up auto_group_dives task ==="

export DISPLAY="${DISPLAY:-:1}"

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any existing Subsurface instances
pkill -9 -f subsurface 2>/dev/null || true
sleep 2

# =====================================================================
# Prepare the dive file: remove all trip groupings from the sample data
# The original SampleDivesV2.ssrf has dives wrapped in <trip> elements.
# We need to remove those wrappers so dives are ungrouped.
# =====================================================================

ORIGINAL_FILE="/opt/subsurface_data/SampleDivesV2.ssrf"
TASK_FILE="/home/ga/Documents/dives.ssrf"

echo "Removing trip groupings from sample data to create starting state..."

# Use Python to properly remove trip elements while preserving dive elements
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import copy

input_file = "/opt/subsurface_data/SampleDivesV2.ssrf"
output_file = "/home/ga/Documents/dives.ssrf"

tree = ET.parse(input_file)
root = tree.getroot()

all_dives = []
trips_to_remove = []

# Collect all dives from trips and mark trips for removal
for trip in root.findall('.//trip'):
    for dive in trip.findall('dive'):
        all_dives.append(copy.deepcopy(dive))
    trips_to_remove.append(trip)

# Collect any top-level dives (just in case)
for dive in root.findall('dive'):
    all_dives.append(copy.deepcopy(dive))

dives_container = root.find('dives')
if dives_container is None:
    dives_container = root

# Remove trips
for trip in trips_to_remove:
    try:
        dives_container.remove(trip)
    except ValueError:
        try:
            root.remove(trip)
        except ValueError:
            pass

# Remove existing top-level dives to avoid duplicates
for dive in dives_container.findall('dive'):
    dives_container.remove(dive)

# Append all collected dives back as ungrouped top-level items
for dive in all_dives:
    dives_container.append(dive)

# Save modified file
tree.write(output_file, xml_declaration=True, encoding='utf-8')
PYEOF

chown ga:ga "$TASK_FILE"
chmod 644 "$TASK_FILE"

# Record initial file state for anti-gaming checks
md5sum "$TASK_FILE" | awk '{print $1}' > /tmp/initial_file_hash.txt
stat -c%Y "$TASK_FILE" > /tmp/initial_file_mtime.txt

# Count initial trips (should be 0)
python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('$TASK_FILE')
print(len(tree.getroot().findall('.//trip')))
" > /tmp/initial_trip_count.txt

# =====================================================================
# Ensure Subsurface autogroup setting is OFF in configuration
# =====================================================================
CONF_FILE="/home/ga/.config/Subsurface/Subsurface.conf"
if [ -f "$CONF_FILE" ]; then
    sed -i '/autogroup/Id' "$CONF_FILE" 2>/dev/null || true
fi

# =====================================================================
# Launch Subsurface with the modified dive file
# =====================================================================
echo "Launching Subsurface..."
xhost +local: 2>/dev/null || true

su - ga -c "DISPLAY=:1 setsid subsurface '$TASK_FILE' >/tmp/subsurface_task.log 2>&1 &"
sleep 5

# Wait for Subsurface window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "subsurface"; then
        echo "Subsurface window detected."
        break
    fi
    sleep 1
done

sleep 3

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and focus the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
SUBSURFACE_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "subsurface" | head -1 | awk '{print $1}')
if [ -n "$SUBSURFACE_WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$SUBSURFACE_WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$SUBSURFACE_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="