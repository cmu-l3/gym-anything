#!/bin/bash
echo "=== Exporting blood_donation_center_layout results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="blood_donation_center_layout"
SH3D_FILE="/home/ga/Documents/SweetHome3D/blood_donation_center_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

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
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'

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
                    data['room_names'].append(rname)
            elif tag == 'wall':
                data['wall_count'] += 1
            elif tag == 'dimensionLine':
                data['dimension_count'] += 1

        data['furniture_count'] = len(data['furniture_names'])

    except Exception as e:
        data['error'] = str(e)

    return data

try:
    with open(baseline_path) as f:
        baseline = json.load(f)
except:
    baseline = {'wall_count': 0, 'dimension_count': 0, 'door_window_count': 0, 'starter_md5': None}

data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

donor_seat_kws = ['armchair', 'recliner', 'lounge', 'sofa', 'bed', 'cot', 'gurney', 'stretcher', 'couch']
chair_kws = ['chair', 'stool', 'seat', 'bench']
desk_kws = ['desk', 'counter', 'reception', 'workstation', 'station']
table_kws = ['table']
storage_kws = ['shelf', 'shelving', 'bookcase', 'cabinet', 'cupboard', 'wardrobe', 'storage', 'rack']
appliance_kws = ['refrigerator', 'fridge', 'cooler', 'microwave', 'oven', 'coffee', 'machine', 'appliance', 'vending']
sink_kws = ['sink', 'basin', 'washbasin', 'lavabo']

donor_seats_count = 0
chair_count = 0
desk_count = 0
table_count = 0
storage_count = 0
appliance_count = 0
sink_count = 0

for name in names:
    if any(kw in name for kw in donor_seat_kws):
        donor_seats_count += 1
    elif any(kw in name for kw in chair_kws):
        chair_count += 1
        
    if any(kw in name for kw in desk_kws):
        desk_count += 1
    elif any(kw in name for kw in table_kws):
        table_count += 1
        
    if any(kw in name for kw in storage_kws):
        storage_count += 1
        
    if any(kw in name for kw in appliance_kws):
        appliance_count += 1
        
    if any(kw in name for kw in sink_kws):
        sink_count += 1

result = {
    'furniture_count': data['furniture_count'],
    'file_found': data['file_found'],
    'file_changed': data['file_md5'] != baseline.get('starter_md5'),
    
    'new_walls': max(0, data['wall_count'] - baseline.get('wall_count', 0)),
    'new_doors': max(0, data['door_window_count'] - baseline.get('door_window_count', 0)),
    'named_rooms': len(data['room_names']),
    'new_dimensions': max(0, data['dimension_count'] - baseline.get('dimension_count', 0)),
    
    'donor_seats_count': donor_seats_count,
    'chair_count': chair_count,
    'desk_count': desk_count,
    'table_count': table_count,
    'storage_count': storage_count,
    'appliance_count': appliance_count,
    'sink_count': sink_count
}

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete. Result:")
print(json.dumps(result, indent=2))
PYEOF