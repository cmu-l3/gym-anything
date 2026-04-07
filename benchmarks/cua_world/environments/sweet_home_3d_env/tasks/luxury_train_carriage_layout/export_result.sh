#!/bin/bash
echo "=== Exporting luxury_train_carriage_layout results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="luxury_train_carriage_layout"
SH3D_FILE="/home/ga/Documents/SweetHome3D/train_carriage_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# 1. Take screenshot for audit evidence
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true
echo "Screenshot captured"

# 2. Graceful save via keyboard shortcut
WID=$(DISPLAY=:1 xdotool search --class sweethome3d 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    echo "Sweet Home 3D window found (WID=$WID), saving..."
    DISPLAY=:1 xdotool windowactivate --sync "$WID" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 4
    echo "Save attempted"
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
        echo "Found newer .sh3d: $CANDIDATE (mtime=$FMTIME vs task_start=$TASK_START)"
        FOUND_FILE="$CANDIDATE"
        break
    fi
done

echo "Using .sh3d file: $FOUND_FILE"

# 5. Parse the .sh3d file to extract metrics
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
            elif tag == 'wall':
                data['wall_count'] += 1
            elif tag == 'dimensionLine':
                data['dimension_count'] += 1

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
    baseline = {'furniture_count': 0, 'starter_md5': None, 'wall_count': 4, 'dimension_count': 0, 'door_window_count': 0}

# Parse current file
data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorise furniture by keyword
bed_kws     = ['bed', 'sofa', 'couch', 'berth', 'cot']
storage_kws = ['wardrobe', 'cabinet', 'closet', 'shelf', 'drawer', 'cupboard', 'dresser']
toilet_kws  = ['toilet', 'wc', 'lavatory', 'bidet']
sink_kws    = ['sink', 'basin', 'washbasin', 'lavabo']
lounge_kws  = ['armchair', 'chair', 'seat', 'sofa', 'couch']
bar_kws     = ['bar', 'counter', 'table', 'desk']
door_kws    = ['door', 'frame', 'window']

# Determine real furniture items (exclude doors/windows)
real_furniture = [n for n in names if not any(kw in n for kw in door_kws)]
data['real_furniture_count'] = len(real_furniture)

data['bed_count']     = sum(1 for n in names if any(kw in n for kw in bed_kws))
data['storage_count'] = sum(1 for n in names if any(kw in n for kw in storage_kws))
data['toilet_count']  = sum(1 for n in names if any(kw in n for kw in toilet_kws))
data['sink_count']    = sum(1 for n in names if any(kw in n for kw in sink_kws))
data['lounge_count']  = sum(1 for n in names if any(kw in n for kw in lounge_kws))
data['bar_count']     = sum(1 for n in names if any(kw in n for kw in bar_kws))

data['new_walls']      = max(0, data['wall_count'] - baseline.get('wall_count', 4))
data['new_dimensions'] = max(0, data['dimension_count'] - baseline.get('dimension_count', 0))

data['file_changed'] = (data['file_md5'] != baseline.get('starter_md5'))

with open(result_path, 'w') as f:
    json.dump(data, f, indent=2)

print("Export data generated:")
print(json.dumps(data, indent=2))
PYEOF

echo "=== Export complete ==="