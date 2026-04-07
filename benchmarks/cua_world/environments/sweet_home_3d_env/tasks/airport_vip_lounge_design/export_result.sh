#!/bin/bash
echo "=== Exporting airport_vip_lounge_design results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="airport_vip_lounge_design"
SH3D_FILE="/home/ga/Documents/SweetHome3D/airport_lounge_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"
TASK_START=$(cat "$START_TS_FILE" 2>/dev/null || echo "0")

# 1. Take snapshot for trajectory logging
take_screenshot "/tmp/${TASK_NAME}_end_screenshot.png"

# 2. Issue grace save
WID=$(DISPLAY=:1 xdotool search --class sweethome3d 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 xdotool windowactivate --sync "$WID" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 4
fi

# 3. Kill application
kill_sweet_home_3d
sleep 3

# 4. Find modified plan file
FOUND_FILE="$SH3D_FILE"
for CANDIDATE in /home/ga/Documents/SweetHome3D/*.sh3d /home/ga/Desktop/*.sh3d /home/ga/*.sh3d; do
    [ -f "$CANDIDATE" ] || continue
    FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
    if [ "$FMTIME" -gt "$TASK_START" ] && [ "$CANDIDATE" != "$SH3D_FILE" ]; then
        FOUND_FILE="$CANDIDATE"
        break
    fi
done

# 5. Search for exported 3D render photo
PHOTO_PATH="/home/ga/Desktop/lounge_render.png"
PHOTO_FOUND="false"
PHOTO_SIZE=0
if [ -f "$PHOTO_PATH" ]; then
    PHOTO_FOUND="true"
    PHOTO_SIZE=$(stat -c %s "$PHOTO_PATH" 2>/dev/null || echo "0")
else
    for CANDIDATE in /home/ga/Desktop/*.png /home/ga/Documents/*.png /home/ga/*.png; do
        [ -f "$CANDIDATE" ] || continue
        FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
        if [ "$FMTIME" -gt "$TASK_START" ]; then
            PHOTO_FOUND="true"
            PHOTO_PATH="$CANDIDATE"
            PHOTO_SIZE=$(stat -c %s "$CANDIDATE" 2>/dev/null || echo "0")
            break
        fi
    done
fi

# 6. Parse metrics from inside the ZIP/XML structure of .sh3d
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'

data = {
    'furniture_names': [], 'room_count': 0, 'room_names': [], 'wall_count': 0,
    'file_found': False, 'file_md5': None,
    'photo_found': ${PHOTO_FOUND}, 'photo_size': ${PHOTO_SIZE}, 'photo_path': '${PHOTO_PATH}'
}

if os.path.exists(sh3d_file):
    data['file_found'] = True
    with open(sh3d_file, 'rb') as f:
        data['file_md5'] = hashlib.md5(f.read()).hexdigest()
    try:
        with zipfile.ZipFile(sh3d_file, 'r') as zf:
            xml_name = next((n for n in zf.namelist() if n.lower() in ('home.xml', 'home')), None)
            if xml_name:
                root = ET.fromstring(zf.read(xml_name))
                for elem in root.iter():
                    tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
                    if tag == 'pieceOfFurniture':
                        data['furniture_names'].append((elem.get('name') or '').lower().strip())
                    elif tag == 'room':
                        data['room_count'] += 1
                        rname = (elem.get('name') or '').strip()
                        if rname:
                            data['room_names'].append(rname)
                    elif tag == 'wall':
                        data['wall_count'] += 1
    except Exception as e:
        data['error'] = str(e)

data['furniture_count'] = len(data['furniture_names'])

# Extract baseline values
try:
    with open(baseline_path) as f:
        baseline = json.load(f)
except:
    baseline = {'wall_count': 0, 'room_count': 0, 'starter_md5': None}

names = data['furniture_names']

# Keyword-based categorization dictionaries 
kw = {
    'chair': ['chair', 'stool', 'seat'],
    'sofa': ['sofa', 'couch', 'armchair', 'settee', 'loveseat', 'lounge'],
    'table': ['table'],
    'desk': ['desk', 'counter', 'workstation', 'reception', 'station'],
    'cabinet': ['cabinet', 'shelf', 'shelving', 'bookcase', 'cupboard', 'storage', 'rack'],
    'appliance': ['refrigerator', 'fridge', 'coffee', 'microwave', 'oven', 'machine', 'appliance'],
    'tv': ['tv', 'television', 'monitor', 'screen', 'display'],
    'plant': ['plant', 'tree', 'flower', 'pot'],
    'toilet': ['toilet', 'wc', 'lavatory', 'bidet'],
    'sink': ['sink', 'basin', 'washbasin']
}

# Aggregate and load category counts
counts = {k: sum(1 for n in names if any(word in n for word in words)) for k, words in kw.items()}
data.update({f"{k}_count": v for k, v in counts.items()})

data['new_walls'] = max(0, data['wall_count'] - baseline.get('wall_count', 0))
data['new_rooms'] = max(0, data['room_count'] - baseline.get('room_count', 0))
data['file_changed'] = data['file_md5'] != baseline.get('starter_md5')

with open(result_path, 'w') as f:
    json.dump(data, f)
PYEOF

chmod 666 "$RESULT_JSON" 2>/dev/null || true
echo "Export complete."