#!/bin/bash
echo "=== Exporting bicycle_shop_repair_cafe results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="bicycle_shop_repair_cafe"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"
TARGET_FILE="/home/ga/Documents/SweetHome3D/bicycle_shop_result.sh3d"

# 1. Take screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# 2. Trigger save
WID=$(DISPLAY=:1 xdotool search --class sweethome3d 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 xdotool windowactivate --sync "$WID" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 4
fi

# 3. Kill app
kill_sweet_home_3d
sleep 3

# 4. Find file
TASK_START=$(cat "$START_TS_FILE" 2>/dev/null || echo "0")
FOUND_FILE=""

if [ -f "$TARGET_FILE" ]; then
    FOUND_FILE="$TARGET_FILE"
else
    for CANDIDATE in /home/ga/Documents/SweetHome3D/*.sh3d /home/ga/Desktop/*.sh3d /home/ga/*.sh3d; do
        [ -f "$CANDIDATE" ] || continue
        FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
        if [ "$FMTIME" -gt "$TASK_START" ]; then
            FOUND_FILE="$CANDIDATE"
            break
        fi
    done
fi

echo "Parsing .sh3d file: $FOUND_FILE"

# 5. Extract JSON
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'

def parse_sh3d(file_path):
    data = {
        'furniture_names': [],
        'door_window_count': 0,
        'room_count': 0,
        'room_names': [],
        'wall_count': 0,
        'dimension_count': 0,
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
            xml_name = next((n for n in ['Home.xml', 'Home', 'home.xml', 'home'] if n in namelist), None)
            if xml_name is None:
                xml_name = next((n for n in namelist if n.endswith('.xml')), None)
            if xml_name is None:
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

    except Exception as e:
        data['error'] = str(e)
    return data

baseline = {}
try:
    with open(baseline_path) as f:
        baseline = json.load(f)
except Exception:
    baseline = {'wall_count': 0, 'door_window_count': 0, 'dimension_count': 0}

data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

desk_kws      = ['desk', 'counter', 'workbench', 'table', 'workstation']
shelf_kws     = ['shelf', 'shelving', 'cabinet', 'bookcase', 'rack', 'wardrobe', 'storage']
chair_kws     = ['chair', 'stool', 'seat', 'bench', 'sofa']
appliance_kws = ['coffee', 'espresso', 'fridge', 'refrigerator', 'microwave', 'appliance', 'machine', 'maker']
sink_kws      = ['sink', 'washbasin', 'basin']
toilet_kws    = ['toilet', 'wc', 'lavatory']

desk_count      = sum(1 for n in names if any(kw in n for kw in desk_kws))
shelf_count     = sum(1 for n in names if any(kw in n for kw in shelf_kws))
chair_count     = sum(1 for n in names if any(kw in n for kw in chair_kws))
appliance_count = sum(1 for n in names if any(kw in n for kw in appliance_kws))
sink_count      = sum(1 for n in names if any(kw in n for kw in sink_kws))
toilet_count    = sum(1 for n in names if any(kw in n for kw in toilet_kws))

output = {
    'file_found': data['file_found'],
    'is_target_filename': '${FOUND_FILE}' == '${TARGET_FILE}',
    'found_file': '${FOUND_FILE}',
    'file_changed': data['file_md5'] != baseline.get('starter_md5') if data['file_md5'] else False,
    'furniture_count': len(names),
    'new_walls': max(0, data['wall_count'] - baseline.get('wall_count', 0)),
    'new_doors': max(0, data['door_window_count'] - baseline.get('door_window_count', 0)),
    'door_window_count': data['door_window_count'],
    'room_count': data['room_count'],
    'room_names': data['room_names'],
    'dimension_count': max(0, data['dimension_count'] - baseline.get('dimension_count', 0)),
    'desk_count': desk_count,
    'shelf_count': shelf_count,
    'chair_count': chair_count,
    'appliance_count': appliance_count,
    'sink_count': sink_count,
    'toilet_count': toilet_count
}

with open(result_path, 'w') as f:
    json.dump(output, f, indent=2)
PYEOF

echo "Result JSON saved to $RESULT_JSON"