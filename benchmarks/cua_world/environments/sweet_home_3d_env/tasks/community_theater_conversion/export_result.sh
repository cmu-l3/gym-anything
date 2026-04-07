#!/bin/bash
echo "=== Exporting community_theater_conversion results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="community_theater_conversion"
SH3D_FILE="/home/ga/Documents/SweetHome3D/theater_starter.sh3d"
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

# 5. Check for 3D Render Image
RENDER_PATH="/home/ga/Desktop/auditorium_render.png"
RENDER_EXISTS="false"
if [ -f "$RENDER_PATH" ]; then
    RMTIME=$(stat -c %Y "$RENDER_PATH" 2>/dev/null || echo "0")
    if [ "$RMTIME" -gt "$TASK_START" ]; then
        RENDER_EXISTS="true"
        echo "Valid 3D render found at $RENDER_PATH"
    fi
fi

# 6. Parse the .sh3d file (Python)
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'
render_exists = ${RENDER_EXISTS}

def parse_sh3d(file_path):
    data = {
        'furniture_names': [],
        'furniture_count': 0,
        'door_window_count': 0,
        'room_count': 0,
        'rooms_with_floor_color': 0,
        'wall_count': 0,
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
            elif tag == 'room':
                data['room_count'] += 1
                has_floor_color = elem.get('floorColor') is not None
                has_floor_texture = False
                for child in elem:
                    child_tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                    if child_tag == 'floorTexture':
                        has_floor_texture = True
                        break
                if has_floor_color or has_floor_texture:
                    data['rooms_with_floor_color'] += 1
            elif tag == 'wall':
                data['wall_count'] += 1

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
    baseline = {'furniture_count': 0, 'starter_md5': None, 'wall_count': 0, 'door_window_count': 0}

# Parse current file
data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorize furniture by keyword
chair_kws    = ['chair', 'seat', 'armchair', 'bench', 'sofa', 'stool', 'fauteuil', 'chaise']
desk_kws     = ['table', 'desk', 'counter', 'bureau']
storage_kws  = ['shelf', 'wardrobe', 'cabinet', 'bookcase', 'storage', 'rack', 'armoire']
plumbing_kws = ['toilet', 'sink', 'wc', 'washbasin', 'lavabo', 'evier']

chair_count    = sum(1 for n in names if any(kw in n for kw in chair_kws))
desk_count     = sum(1 for n in names if any(kw in n for kw in desk_kws))
storage_count  = sum(1 for n in names if any(kw in n for kw in storage_kws))
plumbing_count = sum(1 for n in names if any(kw in n for kw in plumbing_kws))

# Calculate deltas
new_walls = max(0, data.get('wall_count', 0) - baseline.get('wall_count', 0))

result = {
    'file_found': data['file_found'],
    'file_changed': data['file_md5'] != baseline.get('starter_md5'),
    'furniture_count': data['furniture_count'],
    'room_count': data['room_count'],
    'rooms_with_floor_color': data['rooms_with_floor_color'],
    'door_window_count': data['door_window_count'],
    'new_walls': new_walls,
    'chair_count': chair_count,
    'desk_count': desk_count,
    'storage_count': storage_count,
    'plumbing_count': plumbing_count,
    'render_exists': render_exists
}

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON saved.")
PYEOF

echo "=== Export Complete ==="