#!/bin/bash
echo "=== Exporting light_manufacturing_facility_layout results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="light_manufacturing_facility_layout"
SH3D_FILE="/home/ga/Documents/SweetHome3D/industrial_shell_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take screenshot for audit evidence
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# Graceful save via keyboard shortcut
WID=$(DISPLAY=:1 xdotool search --class sweethome3d 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 xdotool windowactivate --sync "$WID" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 4
fi

kill_sweet_home_3d
sleep 3

TASK_START=$(cat "$START_TS_FILE" 2>/dev/null || echo "0")
FOUND_FILE=""

# Check if agent modified the starter or used 'Save As'
if [ -f "$SH3D_FILE" ]; then
    FOUND_FILE="$SH3D_FILE"
fi

for CANDIDATE in /home/ga/Documents/SweetHome3D/*.sh3d /home/ga/Desktop/*.sh3d /home/ga/*.sh3d; do
    [ -f "$CANDIDATE" ] || continue
    FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
    if [ "$FMTIME" -gt "$TASK_START" ] && [ "$CANDIDATE" != "$SH3D_FILE" ]; then
        FOUND_FILE="$CANDIDATE"
        break
    fi
done

python3 << PYEOF
import zipfile, json, hashlib, os
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
        'label_count': 0,
        'label_texts': [],
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
            if not xml_name:
                xml_name = next((n for n in namelist if n.endswith('.xml')), None)
            if not xml_name:
                return data

            content = zf.read(xml_name)
            root = ET.fromstring(content)

        for elem in root.iter():
            tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
            if tag == 'pieceOfFurniture':
                if elem.get('doorOrWindow', '').lower() == 'true':
                    data['door_window_count'] += 1
                else:
                    name = (elem.get('name') or '').lower().strip()
                    data['furniture_names'].append(name)
            elif tag == 'room':
                data['room_count'] += 1
                rname = (elem.get('name') or '').strip()
                if rname:
                    data['room_names'].append(rname.lower())
            elif tag == 'wall':
                data['wall_count'] += 1
            elif tag == 'label':
                data['label_count'] += 1
                ltext = (elem.get('text') or '').strip()
                if ltext:
                    data['label_texts'].append(ltext.lower())

    except Exception:
        pass
    return data

baseline = {'wall_count': 0, 'door_window_count': 0, 'starter_md5': None}
try:
    with open(baseline_path) as f:
        baseline = json.load(f)
except Exception:
    pass

data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Domain-specific industrial/office keyword extraction
work_surface_kws = ['table', 'workbench', 'desk', 'station', 'counter', 'workstation']
seating_kws      = ['chair', 'stool', 'seat', 'bench', 'armchair', 'sofa']
storage_kws      = ['shelf', 'shelving', 'rack', 'cabinet', 'bookcase', 'cupboard', 'storage', 'wardrobe']
appliance_kws    = ['refrigerator', 'fridge', 'microwave', 'oven', 'coffee', 'cooler', 'kettle', 'machine', 'appliance']
sink_kws         = ['sink', 'basin', 'washbasin', 'lavabo']
computer_kws     = ['computer', 'laptop', 'screen', 'pc', 'monitor', 'tv', 'display', 'imac']

work_surface_count = sum(1 for n in names if any(kw in n for kw in work_surface_kws))
seating_count      = sum(1 for n in names if any(kw in n for kw in seating_kws))
storage_count      = sum(1 for n in names if any(kw in n for kw in storage_kws))
appliance_count    = sum(1 for n in names if any(kw in n for kw in appliance_kws))
sink_count         = sum(1 for n in names if any(kw in n for kw in sink_kws))
computer_count     = sum(1 for n in names if any(kw in n for kw in computer_kws))

new_walls = max(0, data['wall_count'] - baseline.get('wall_count', 0))
new_doors = max(0, data['door_window_count'] - baseline.get('door_window_count', 0))
file_changed = data.get('file_md5') != baseline.get('starter_md5')

result = {
    'file_found': data['file_found'],
    'file_changed': file_changed,
    'furniture_count': len(names),
    'work_surface_count': work_surface_count,
    'seating_count': seating_count,
    'storage_count': storage_count,
    'appliance_count': appliance_count,
    'sink_count': sink_count,
    'computer_count': computer_count,
    'new_walls': new_walls,
    'new_doors': new_doors,
    'room_count': data['room_count'],
    'room_names': data['room_names'],
    'label_count': data['label_count'],
    'label_texts': data['label_texts']
}

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="