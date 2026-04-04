#!/bin/bash
echo "=== Exporting open_plan_office_renovation results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="open_plan_office_renovation"
SH3D_FILE="/home/ga/Documents/SweetHome3D/open_plan_office_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# ── Step 1: Take screenshot for audit evidence ─────────────────────────────────
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true
echo "Screenshot captured"

# ── Step 2: Graceful save via keyboard shortcut ────────────────────────────────
WID=$(DISPLAY=:1 xdotool search --class sweethome3d 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    echo "Sweet Home 3D window found (WID=$WID), saving..."
    DISPLAY=:1 xdotool windowactivate --sync "$WID" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 4
    echo "Save attempted"
fi

# ── Step 3: Kill Sweet Home 3D ────────────────────────────────────────────────
kill_sweet_home_3d
sleep 3

# ── Step 4: Find the task .sh3d file ──────────────────────────────────────────
TASK_START=$(cat "$START_TS_FILE" 2>/dev/null || echo "0")
FOUND_FILE=""

if [ -f "$SH3D_FILE" ]; then
    FOUND_FILE="$SH3D_FILE"
fi

for CANDIDATE in /home/ga/Documents/SweetHome3D/*.sh3d /home/ga/Desktop/*.sh3d /home/ga/*.sh3d; do
    [ -f "$CANDIDATE" ] || continue
    FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
    if [ "$FMTIME" -gt "$TASK_START" ] && [ "$CANDIDATE" != "$SH3D_FILE" ]; then
        echo "Found newer .sh3d: $CANDIDATE (mtime=$FMTIME vs task_start=$TASK_START)"
        FOUND_FILE="$CANDIDATE"
        break
    fi
done

echo "Using .sh3d file: $FOUND_FILE"

# ── Step 5: Parse the .sh3d file (enhanced: rooms, doors/windows, floor colors) ─
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'

def parse_sh3d(file_path):
    data = {
        'furniture_names': [], 'furniture_count': 0,
        'door_window_count': 0,
        'room_count': 0, 'room_names': [], 'rooms_with_floor_color': 0,
        'wall_count': 0,
        'label_count': 0, 'label_texts': [],
        'file_found': False, 'file_md5': None
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
                data['furniture_names'].append(name)
                if elem.get('doorOrWindow', '').lower() == 'true':
                    data['door_window_count'] += 1
            elif tag == 'room':
                data['room_count'] += 1
                rname = (elem.get('name') or '').strip()
                if rname:
                    data['room_names'].append(rname.lower())
                if elem.get('floorColor') or elem.get('floorTexture'):
                    data['rooms_with_floor_color'] += 1
            elif tag == 'wall':
                data['wall_count'] += 1
            elif tag == 'label':
                data['label_count'] += 1
                ltext = (elem.get('text') or '').strip()
                if ltext:
                    data['label_texts'].append(ltext.lower())
        data['furniture_count'] = len(data['furniture_names'])
    except Exception as e:
        data['error'] = str(e)
    return data

baseline = {}
try:
    with open(baseline_path) as f:
        baseline = json.load(f)
except Exception:
    baseline = {'furniture_count': 0, 'starter_md5': None, 'room_count': 0, 'door_window_count': 0}

data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

desk_kws      = ['desk', 'workstation', 'counter', 'station']
chair_kws     = ['chair', 'stool', 'seat', 'armchair']
sofa_kws      = ['sofa', 'couch', 'settee', 'loveseat']
table_kws     = ['table', 'coffee table']
bookcase_kws  = ['bookcase', 'bookshelf', 'shelf', 'shelving', 'cabinet', 'cupboard', 'wardrobe', 'storage', 'rack']
appliance_kws = ['refrigerator', 'fridge', 'oven', 'microwave', 'stove', 'cooker', 'dishwasher', 'freezer']
lamp_kws      = ['lamp', 'light', 'sconce', 'chandelier', 'ceiling light', 'spotlight']
plant_kws     = ['plant', 'flower', 'tree', 'vase', 'pot']
art_kws       = ['painting', 'picture', 'frame', 'art', 'poster', 'photo', 'mirror']

desk_count      = sum(1 for n in names if any(kw in n for kw in desk_kws))
chair_count     = sum(1 for n in names if any(kw in n for kw in chair_kws))
sofa_count      = sum(1 for n in names if any(kw in n for kw in sofa_kws))
table_count     = sum(1 for n in names if any(kw in n for kw in table_kws))
bookcase_count  = sum(1 for n in names if any(kw in n for kw in bookcase_kws))
appliance_count = sum(1 for n in names if any(kw in n for kw in appliance_kws))
decor_count     = sum(1 for n in names if any(kw in n for kw in lamp_kws + plant_kws + art_kws))

new_rooms = data['room_count'] - baseline.get('room_count', 0)
new_doors = data['door_window_count'] - baseline.get('door_window_count', 0)

all_kws = desk_kws + chair_kws + sofa_kws + table_kws + bookcase_kws + appliance_kws + lamp_kws + plant_kws + art_kws
type_set = set()
for n in names:
    for kw in all_kws:
        if kw in n:
            type_set.add(kw)
distinct_types = len(type_set)

result = {
    'furniture_count': data['furniture_count'],
    'room_count': data['room_count'],
    'wall_count': data['wall_count'],
    'door_window_count': data['door_window_count'],
    'rooms_with_floor_color': data.get('rooms_with_floor_color', 0),
    'new_rooms': max(0, new_rooms),
    'new_doors': max(0, new_doors),
    'room_names': data.get('room_names', []),
    'desk_count': desk_count,
    'chair_count': chair_count,
    'sofa_count': sofa_count,
    'table_count': table_count,
    'bookcase_count': bookcase_count,
    'appliance_count': appliance_count,
    'decor_count': decor_count,
    'distinct_types': distinct_types,
    'furniture_names_sample': names[:40],
    'file_found': data['file_found'],
    'file_md5': data.get('file_md5'),
    'baseline_md5': baseline.get('starter_md5'),
    'file_changed': data.get('file_md5') != baseline.get('starter_md5'),
    'error': data.get('error')
}

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== open_plan_office_renovation export complete ==="
