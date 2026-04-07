#!/bin/bash
echo "=== Setting up broken_mission_repair task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Create the broken mission file from sample_mission.plan by injecting errors
python3 << 'PYEOF'
import json
import os
import shutil

src = '/workspace/data/sample_mission.plan'
dst = '/home/ga/Documents/QGC/incoming_mission.plan'

with open(src, 'r') as f:
    plan = json.load(f)

items = plan['mission']['items']

# ERROR 1: items[1] is first nav waypoint — set altitude to dangerously low 5m
items[1]['Altitude'] = 5
if 'params' in items[1] and len(items[1]['params']) >= 7:
    items[1]['params'][6] = 5

# ERROR 2: items[3] is third nav waypoint — set altitude to 5m
items[3]['Altitude'] = 5
if 'params' in items[3] and len(items[3]['params']) >= 7:
    items[3]['params'][6] = 5

# ERROR 3: items[4] is fourth nav waypoint — set altitude to extreme 350m
items[4]['Altitude'] = 350
if 'params' in items[4] and len(items[4]['params']) >= 7:
    items[4]['params'][6] = 350

# ERROR 4: Remove the RTL item (last item, command=20)
# Find and remove RTL (command 20)
rtl_indices = [i for i, item in enumerate(items) if item.get('command') == 20]
for idx in reversed(rtl_indices):
    items.pop(idx)

plan['mission']['items'] = items

with open(dst, 'w') as f:
    json.dump(plan, f, indent=4)

# Set ownership to ga
os.system(f'chown ga:ga {dst}')
print("Broken mission written.")
PYEOF

# 3. Record task start time
date +%s > /tmp/task_start_time

# 4. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 5. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 6. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 7. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== broken_mission_repair task setup complete ==="
echo "Broken mission: /home/ga/Documents/QGC/incoming_mission.plan"
echo "Expected output: /home/ga/Documents/QGC/fixed_mission.plan"
