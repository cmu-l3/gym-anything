#!/bin/bash
echo "=== Exporting pottery_studio_layout results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="pottery_studio_layout"
SH3D_FILE="/home/ga/Documents/SweetHome3D/pottery_studio_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Take screenshot of final application state
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# Save gracefully via UI interaction
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
FOUND_FILE="$SH3D_FILE"

# Look for the modified file (the agent might have used Save As)
for CANDIDATE in /home/ga/Documents/SweetHome3D/*.sh3d /home/ga/Desktop/*.sh3d /home/ga/*.sh3d; do
    [ -f "$CANDIDATE" ] || continue
    FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
    if [ "$FMTIME" -gt "$TASK_START" ] && [ "$CANDIDATE" != "$SH3D_FILE" ]; then
        FOUND_FILE="$CANDIDATE"
        break
    fi
done

echo "Using .sh3d file: $FOUND_FILE"

# Parse the resulting .sh3d file and generate the JSON result
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'
task_start = int('${TASK_START}' or '0')

def parse_sh3d(file_path):
    data = {
        'furniture_names': [], 'furniture_count': 0,
        'room_names': [], 'room_count': 0, 'rooms_with_floor_color': 0,
        'wall_count': 0, 'dimension_count': 0,
        'file_found': False, 'file_md5': None, 'file_mtime': 0
    }
    if not os.path.exists(file_path):
        return data

    data['file_found'] = True
    data['file_mtime'] = int(os.path.getmtime(file_path))
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
                data['furniture_names'].append((elem.get('name') or '').lower().strip())
            elif tag == 'room':
                data['room_count'] += 1
                rname = (elem.get('name') or '').strip().lower()
                if rname:
                    data['room_names'].append(rname)
                
                has_color = elem.get('floorColor') is not None
                has_texture = any(child.tag.split('}')[-1] == 'floorTexture' for child in elem)
                if has_color or has_texture:
                    data['rooms_with_floor_color'] += 1
            elif tag == 'wall':
                data['wall_count'] += 1
            elif tag == 'dimensionLine':
                data['dimension_count'] += 1

        data['furniture_count'] = len(data['furniture_names'])
    except Exception as e:
        data['error'] = str(e)

    return data

baseline = {}
try:
    with open(baseline_path) as f:
        baseline = json.load(f)
except Exception:
    baseline = {'wall_count': 0, 'dimension_count': 0, 'room_count': 0, 'starter_md5': None}

data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorize furniture via keywords
chair_kws = ['chair', 'stool', 'seat', 'bench']
table_kws = ['table', 'desk', 'counter', 'workstation', 'cylinder']
sink_kws = ['sink', 'basin', 'washbasin']
shelf_kws = ['shelf', 'shelving', 'bookcase', 'rack', 'storage', 'wardrobe', 'cabinet']
kiln_kws = ['machine', 'dryer', 'oven', 'washer', 'kiln', 'boiler', 'heater']
plant_kws = ['plant', 'flower', 'tree', 'pot']

data['chair_count'] = sum(1 for n in names if any(kw in n for kw in chair_kws))
data['table_count'] = sum(1 for n in names if any(kw in n for kw in table_kws))
data['sink_count'] = sum(1 for n in names if any(kw in n for kw in sink_kws))
data['shelf_count'] = sum(1 for n in names if any(kw in n for kw in shelf_kws))
data['kiln_count'] = sum(1 for n in names if any(kw in n for kw in kiln_kws))
data['plant_count'] = sum(1 for n in names if any(kw in n for kw in plant_kws))

# Calculate deltas for annotations and walls
data['new_walls'] = max(0, data['wall_count'] - baseline.get('wall_count', 0))
data['new_dimensions'] = max(0, data['dimension_count'] - baseline.get('dimension_count', 0))

# Anti-gaming verification check
file_changed = False
if data.get('file_found'):
    if data.get('file_md5') != baseline.get('starter_md5'):
        file_changed = True
    if data.get('file_mtime', 0) > task_start:
        file_changed = True
data['file_changed'] = file_changed

with open(result_path, 'w') as f:
    json.dump(data, f, indent=2)

print(json.dumps(data, indent=2))
PYEOF

echo "=== Export complete ==="