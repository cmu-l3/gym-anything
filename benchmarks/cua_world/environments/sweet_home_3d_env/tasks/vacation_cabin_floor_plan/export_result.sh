#!/bin/bash
echo "=== Exporting vacation_cabin_floor_plan results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="vacation_cabin_floor_plan"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"
TARGET_FILE="/home/ga/Documents/SweetHome3D/vacation_cabin.sh3d"

# Take screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true
echo "Screenshot captured"

# Wait, we can attempt a save but Sweet Home 3D prompts for a filename if it's new.
# Since the agent must save it manually, if they didn't, we will miss it. We can try to hit Ctrl+S anyway.
# But if it opens a dialog, it just hangs, which is fine since we kill it immediately after.
WID=$(DISPLAY=:1 xdotool search --class sweethome3d 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    echo "Sweet Home 3D window found (WID=$WID), attempting save..."
    DISPLAY=:1 xdotool windowactivate --sync "$WID" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 4
fi

kill_sweet_home_3d
sleep 3

TASK_START=$(cat "$START_TS_FILE" 2>/dev/null || echo "0")
FOUND_FILE=""

if [ -f "$TARGET_FILE" ]; then
    FOUND_FILE="$TARGET_FILE"
fi

if [ -z "$FOUND_FILE" ]; then
    # Look for any newly created .sh3d file
    for CANDIDATE in /home/ga/Documents/SweetHome3D/*.sh3d /home/ga/Desktop/*.sh3d /home/ga/*.sh3d; do
        [ -f "$CANDIDATE" ] || continue
        FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
        if [ "$FMTIME" -gt "$TASK_START" ]; then
            echo "Found newer .sh3d: $CANDIDATE (mtime=$FMTIME vs task_start=$TASK_START)"
            FOUND_FILE="$CANDIDATE"
            break
        fi
    done
fi

echo "Using .sh3d file: $FOUND_FILE"

# Parse the .sh3d file
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'

def parse_sh3d(file_path):
    data = {
        'furniture_names': [],
        'furniture_count': 0,
        'door_window_count': 0,
        'room_count': 0,
        'room_names': [],
        'wall_count': 0,
        'dimension_count': 0,
        'file_found': False,
        'file_md5': None
    }
    if not file_path or not os.path.exists(file_path):
        return data

    data['file_found'] = True
    with open(file_path, 'rb') as f:
        data['file_md5'] = hashlib.md5(f.read()).hexdigest()

    try:
        with zipfile.ZipFile(file_path, 'r') as zf:
            namelist = zf.namelist()
            xml_name = None
            for candidate in ['Home.xml', 'Home', 'home.xml', 'home']:
                if candidate in namelist:
                    xml_name = candidate
                    break
            if xml_name is None:
                for n in namelist:
                    if n.endswith('.xml'):
                        xml_name = n
                        break
            if xml_name is None:
                data['error'] = 'no_xml_found'
                return data

            content = zf.read(xml_name)
            root = ET.fromstring(content)

        for elem in root.iter():
            tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
            if tag == 'pieceOfFurniture':
                name = (elem.get('name') or '').lower().strip()
                data['furniture_names'].append(name)
                if elem.get('doorOrWindow', '').lower() == 'true':
                    data['door_window_count'] += 1
            elif tag == 'room':
                data['room_count'] += 1
                rname = (elem.get('name') or '').strip()
                if rname:
                    data['room_names'].append(rname.lower())
            elif tag == 'wall':
                data['wall_count'] += 1
            elif tag == 'dimensionLine':
                data['dimension_count'] += 1

        data['furniture_count'] = len(data['furniture_names'])

    except Exception as e:
        data['error'] = str(e)

    return data

data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

bed_kws     = ['bed', 'mattress', 'bunk', 'cot']
sofa_kws    = ['sofa', 'couch', 'loveseat', 'settee', 'armchair']
table_kws   = ['table', 'desk', 'counter', 'dining']
chair_kws   = ['chair', 'stool', 'seat', 'bench']
appliance_kws = ['refrigerator', 'fridge', 'stove', 'oven', 'microwave', 'dishwasher', 'washer', 'dryer', 'range', 'cooker']
toilet_kws  = ['toilet', 'wc', 'lavatory']
sink_kws    = ['sink', 'basin', 'washbasin', 'lavabo']

data['bed_count'] = sum(1 for n in names if any(kw in n for kw in bed_kws))
data['sofa_count'] = sum(1 for n in names if any(kw in n for kw in sofa_kws))
data['table_count'] = sum(1 for n in names if any(kw in n for kw in table_kws))
data['chair_count'] = sum(1 for n in names if any(kw in n for kw in chair_kws))
data['appliance_count'] = sum(1 for n in names if any(kw in n for kw in appliance_kws))
data['toilet_count'] = sum(1 for n in names if any(kw in n for kw in toilet_kws))
data['sink_count'] = sum(1 for n in names if any(kw in n for kw in sink_kws))

with open(result_path, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Exported metrics to {result_path}")
PYEOF

chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "=== Export complete ==="