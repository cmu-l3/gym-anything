#!/bin/bash
echo "=== Exporting daycare_center_conversion results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="daycare_center_conversion"
SH3D_FILE="/home/ga/Documents/SweetHome3D/daycare_center_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# 1. Take screenshot for audit evidence
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true
echo "Final screenshot captured."

# 2. Graceful save via keyboard shortcut
WID=$(DISPLAY=:1 xdotool search --class sweethome3d 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    echo "Sweet Home 3D window found (WID=$WID), saving..."
    DISPLAY=:1 xdotool windowactivate --sync "$WID" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 4
    echo "Save attempted."
fi

# 3. Kill Sweet Home 3D
kill_sweet_home_3d
sleep 3

# 4. Find the correct .sh3d file
TASK_START=$(cat "$START_TS_FILE" 2>/dev/null || echo "0")
FOUND_FILE=""

if [ -f "$SH3D_FILE" ]; then
    FOUND_FILE="$SH3D_FILE"
fi

# Check if the agent saved it under a different name
for CANDIDATE in /home/ga/Documents/SweetHome3D/*.sh3d /home/ga/Desktop/*.sh3d /home/ga/*.sh3d; do
    [ -f "$CANDIDATE" ] || continue
    FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
    if [ "$FMTIME" -gt "$TASK_START" ] && [ "$CANDIDATE" != "$SH3D_FILE" ]; then
        echo "Found newer .sh3d: $CANDIDATE (mtime=$FMTIME vs task_start=$TASK_START)"
        FOUND_FILE="$CANDIDATE"
        break
    fi
done

echo "Parsing .sh3d file: $FOUND_FILE"

# 5. Parse the .sh3d file for scoring features
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'
task_start = int('${TASK_START}' or '0')

def parse_sh3d(file_path):
    data = {
        'furniture_names': [],
        'furniture_count': 0,
        'door_window_count': 0,
        'room_count': 0,
        'named_room_count': 0,
        'room_names': [],
        'wall_count': 0,
        'polyline_count': 0,
        'file_found': False,
        'file_md5': None
    }
    if not os.path.exists(file_path):
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
                cat_id = (elem.get('catalogId') or '').lower().strip()
                combined_text = f"{name} {cat_id}"
                data['furniture_names'].append(combined_text)
                if elem.get('doorOrWindow', '').lower() == 'true':
                    data['door_window_count'] += 1
            elif tag == 'room':
                data['room_count'] += 1
                rname = (elem.get('name') or '').strip()
                if rname:
                    data['named_room_count'] += 1
                    data['room_names'].append(rname)
            elif tag == 'wall':
                data['wall_count'] += 1
            elif tag == 'polyline':
                data['polyline_count'] += 1

        data['furniture_count'] = len(data['furniture_names'])

    except Exception as e:
        data['error'] = str(e)

    return data

# Load baseline
baseline = {}
try:
    with open(baseline_path) as f:
        baseline = json.load(f)
except Exception:
    baseline = {'wall_count': 0, 'room_count': 0, 'polyline_count': 0, 'starter_md5': None}

data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorize furniture
chair_kws      = ['chair', 'stool', 'seat', 'armchair', 'bench']
table_kws      = ['table']
desk_kws       = ['desk', 'workstation', 'counter', 'station']
bed_kws        = ['bed', 'crib', 'cot', 'cradle', 'bunk']
appliance_kws  = ['refrigerator', 'fridge', 'oven', 'stove', 'microwave', 'dishwasher', 'washer', 'dryer', 'cooker', 'freezer']
toilet_kws     = ['toilet', 'wc', 'lavatory']
sink_kws       = ['sink', 'basin', 'washbasin', 'lavabo', 'faucet']
shelf_kws      = ['shelf', 'shelving', 'bookcase', 'bookshelf', 'cabinet', 'cupboard', 'wardrobe', 'storage', 'rack', 'locker']

def count_items(kws, exclusion_kws=None):
    count = 0
    for n in names:
        if any(kw in n for kw in kws):
            if exclusion_kws and any(ex in n for ex in exclusion_kws):
                continue
            count += 1
    return count

chair_count     = count_items(chair_kws)
table_count     = count_items(table_kws, exclusion_kws=['desk', 'workstation']) # separate tables from desks
desk_count      = count_items(desk_kws)
bed_count       = count_items(bed_kws)
appliance_count = count_items(appliance_kws)
toilet_count    = count_items(toilet_kws)
sink_count      = count_items(sink_kws)
shelf_count     = count_items(shelf_kws)

new_walls = max(0, data.get('wall_count', 0) - baseline.get('wall_count', 0))
new_polylines = max(0, data.get('polyline_count', 0) - baseline.get('polyline_count', 0))
file_changed = data.get('file_md5') != baseline.get('starter_md5')

export_result = {
    'file_found': data.get('file_found', False),
    'file_changed': file_changed,
    'furniture_count': data.get('furniture_count', 0),
    'chair_count': chair_count,
    'table_count': table_count,
    'desk_count': desk_count,
    'bed_count': bed_count,
    'appliance_count': appliance_count,
    'toilet_count': toilet_count,
    'sink_count': sink_count,
    'shelf_count': shelf_count,
    'new_walls': new_walls,
    'named_room_count': data.get('named_room_count', 0),
    'room_names': data.get('room_names', []),
    'new_polylines': new_polylines,
    'error': data.get('error', None)
}

with open(result_path, 'w') as f:
    json.dump(export_result, f, indent=2)

print(json.dumps(export_result, indent=2))
PYEOF

echo "=== Export Complete ==="