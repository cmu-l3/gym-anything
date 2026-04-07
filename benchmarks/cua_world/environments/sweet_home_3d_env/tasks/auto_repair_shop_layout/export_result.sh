#!/bin/bash
echo "=== Exporting auto_repair_shop_layout results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="auto_repair_shop_layout"
SH3D_FILE="/home/ga/Documents/SweetHome3D/auto_repair_shop_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# 1. Take screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true
echo "Screenshot captured"

# 2. Graceful save
WID=$(DISPLAY=:1 xdotool search --class sweethome3d 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    echo "Sweet Home 3D window found (WID=$WID), saving..."
    DISPLAY=:1 xdotool windowactivate --sync "$WID" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 4
fi

# 3. Kill Sweet Home 3D
kill_sweet_home_3d
sleep 3

# 4. Find the task .sh3d file
TASK_START=$(cat "$START_TS_FILE" 2>/dev/null || echo "0")
FOUND_FILE=""

if [ -f "$SH3D_FILE" ]; then
    FOUND_FILE="$SH3D_FILE"
fi

for CANDIDATE in /home/ga/Documents/SweetHome3D/*.sh3d /home/ga/Desktop/*.sh3d /home/ga/*.sh3d; do
    [ -f "$CANDIDATE" ] || continue
    FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
    if [ "$FMTIME" -gt "$TASK_START" ] && [ "$CANDIDATE" != "$SH3D_FILE" ]; then
        echo "Found newer .sh3d: $CANDIDATE"
        FOUND_FILE="$CANDIDATE"
        break
    fi
done

echo "Using .sh3d file: $FOUND_FILE"

# 5. Parse the .sh3d file
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
        'rooms_with_names': 0,
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
            xml_name = next((n for n in namelist if n.lower() == 'home.xml'), None)
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
                    data['rooms_with_names'] += 1
                    data['room_names'].append(rname)
            elif tag == 'wall':
                data['wall_count'] += 1
            elif tag == 'label':
                ltext = (elem.get('text') or '').strip()
                if ltext:
                    data['label_count'] += 1
                    data['label_texts'].append(ltext)

        data['furniture_count'] = len(data['furniture_names'])

    except Exception as e:
        data['error'] = str(e)

    return data

# Load baseline
try:
    with open(baseline_path) as f:
        baseline = json.load(f)
except Exception:
    baseline = {'wall_count': 4, 'starter_md5': None}

data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Keywords
table_kws  = ['table', 'workbench', 'bench']
desk_kws   = ['desk', 'counter', 'reception', 'workstation']
shelf_kws  = ['shelf', 'shelving', 'bookcase', 'cabinet', 'cupboard', 'rack', 'storage', 'wardrobe']
chair_kws  = ['chair', 'stool', 'seat', 'armchair', 'sofa', 'couch']
lamp_kws   = ['lamp', 'light', 'sconce', 'chandelier', 'fixture']
toilet_kws = ['toilet', 'wc', 'lavatory']
sink_kws   = ['sink', 'basin', 'washbasin']

data['table_count'] = sum(1 for n in names if any(kw in n for kw in table_kws))
data['desk_count'] = sum(1 for n in names if any(kw in n for kw in desk_kws))
data['shelf_count'] = sum(1 for n in names if any(kw in n for kw in shelf_kws))
data['chair_count'] = sum(1 for n in names if any(kw in n for kw in chair_kws))
data['lamp_count'] = sum(1 for n in names if any(kw in n for kw in lamp_kws))
data['toilet_count'] = sum(1 for n in names if any(kw in n for kw in toilet_kws))
data['sink_count'] = sum(1 for n in names if any(kw in n for kw in sink_kws))

# Deltas
data['new_walls'] = max(0, data['wall_count'] - baseline.get('wall_count', 4))
data['file_changed'] = (data['file_md5'] != baseline.get('starter_md5'))

with open(result_path, 'w') as f:
    json.dump(data, f, indent=2)

print("Extraction complete.")
PYEOF

cat "$RESULT_JSON"
echo "=== Export Complete ==="