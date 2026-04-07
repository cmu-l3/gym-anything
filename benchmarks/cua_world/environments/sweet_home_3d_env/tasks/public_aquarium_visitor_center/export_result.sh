#!/bin/bash
echo "=== Exporting public_aquarium_visitor_center results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="public_aquarium_visitor_center"
SH3D_FILE="/home/ga/Documents/SweetHome3D/aquarium_shell_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take screenshot for audit evidence
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true
echo "Screenshot captured"

# Graceful save via keyboard shortcut
WID=$(DISPLAY=:1 xdotool search --class sweethome3d 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    echo "Sweet Home 3D window found (WID=$WID), saving..."
    DISPLAY=:1 xdotool windowactivate --sync "$WID" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 4
    echo "Save attempted"
fi

# Kill Sweet Home 3D
kill_sweet_home_3d
sleep 3

# Find the task .sh3d file
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

# Parse the .sh3d file
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'

def parse_sh3d(file_path):
    data = {
        'furniture_names': [],
        'room_names': [],
        'label_texts': [],
        'wall_count': 0,
        'polylines': [],
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
            xml_name = next((c for c in ['Home.xml', 'Home', 'home.xml', 'home'] if c in namelist), None)
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
                # Ignore doors/windows for furniture count in this logic
                if elem.get('doorOrWindow', '').lower() != 'true':
                    name = (elem.get('name') or '').lower().strip()
                    data['furniture_names'].append(name)
            elif tag == 'room':
                rname = (elem.get('name') or '').strip()
                if rname:
                    data['room_names'].append(rname)
            elif tag == 'wall':
                data['wall_count'] += 1
            elif tag == 'label':
                ltext = (elem.get('text') or '').strip()
                if ltext:
                    data['label_texts'].append(ltext)
            elif tag == 'polyline':
                points = sum(1 for child in elem if 'point' in child.tag.lower() or child.tag.endswith('point'))
                data['polylines'].append(points)

        data['furniture_count'] = len(data['furniture_names'])

    except Exception as e:
        data['error'] = str(e)

    return data

baseline = {}
try:
    with open(baseline_path) as f:
        baseline = json.load(f)
except Exception:
    baseline = {'wall_count': 0}

data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorize furniture by keyword
shelf_kws = ['shelf', 'shelving', 'bookcase', 'cabinet', 'display', 'storage', 'rack']
chair_kws = ['chair', 'stool', 'seat', 'bench']
desk_kws = ['desk', 'table', 'counter', 'station']

shelf_count = sum(1 for n in names if any(kw in n for kw in shelf_kws))
chair_count = sum(1 for n in names if any(kw in n for kw in chair_kws))
desk_count = sum(1 for n in names if any(kw in n for kw in desk_kws))

output = {
    'file_found': data.get('file_found', False),
    'file_md5': data.get('file_md5'),
    'furniture_count': data.get('furniture_count', 0),
    'shelf_count': shelf_count,
    'chair_count': chair_count,
    'desk_count': desk_count,
    'room_names': data.get('room_names', []),
    'label_texts': data.get('label_texts', []),
    'polylines': data.get('polylines', []),
    'new_walls': max(0, data.get('wall_count', 0) - baseline.get('wall_count', 0)),
    'file_changed': data.get('file_md5') != baseline.get('starter_md5') and baseline.get('starter_md5') is not None
}

with open(result_path, 'w') as f:
    json.dump(output, f, indent=2)

PYEOF

chown ga:ga "$RESULT_JSON" 2>/dev/null || true
echo "Export Complete."