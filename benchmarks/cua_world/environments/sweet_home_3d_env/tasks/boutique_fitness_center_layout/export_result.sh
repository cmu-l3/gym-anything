#!/bin/bash
echo "=== Exporting boutique_fitness_center_layout results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="boutique_fitness_center_layout"
SH3D_FILE="/home/ga/Documents/SweetHome3D/fitness_center_starter.sh3d"
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

# ── Step 5: Check for 3D Photo Render ─────────────────────────────────────────
RENDER_FOUND="false"
RENDER_PATH=""
for CANDIDATE in /home/ga/Desktop/*.png /home/ga/Desktop/*.jpg /home/ga/Documents/*.png; do
    [ -f "$CANDIDATE" ] || continue
    FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
    if [ "$FMTIME" -gt "$TASK_START" ] && [[ "$(basename "$CANDIDATE")" != screenshot* ]]; then
        echo "Found potential render image: $CANDIDATE"
        RENDER_FOUND="true"
        RENDER_PATH="$CANDIDATE"
        break
    fi
done

# ── Step 6: Parse the .sh3d file ──────────────────────────────────────────────
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'
render_found = ${RENDER_FOUND}
task_start = int('${TASK_START}')

def parse_sh3d(file_path):
    data = {
        'furniture_names': [],
        'furniture_count': 0,
        'room_count': 0,
        'room_names': [],
        'rooms_with_floor_color': 0,
        'wall_count': 0,
        'label_count': 0,
        'file_found': False,
        'file_md5': None,
        'file_changed': False
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
            elif tag == 'room':
                data['room_count'] += 1
                rname = (elem.get('name') or '').strip()
                if rname:
                    data['room_names'].append(rname.lower())
                # Check for floor color or texture
                if elem.get('floorColor') is not None:
                    data['rooms_with_floor_color'] += 1
                else:
                    for child in elem:
                        child_tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                        if child_tag == 'floorTexture':
                            data['rooms_with_floor_color'] += 1
                            break
            elif tag == 'wall':
                data['wall_count'] += 1
            elif tag == 'label':
                data['label_count'] += 1

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
    baseline = {'furniture_count': 0, 'starter_md5': None, 'wall_count': 0, 'room_count': 0, 'label_count': 0}

# Parse current file
data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorize furniture
gym_kws       = ['treadmill', 'elliptical', 'bike', 'weight', 'sport', 'cross', 'fitness', 'gym', 'bench press']
desk_kws      = ['desk', 'counter', 'workstation', 'table']
chair_kws     = ['chair', 'stool', 'seat']
lounge_kws    = ['sofa', 'armchair', 'couch', 'loveseat', 'settee', 'bench'] # bench might be weight bench, handled safely later
storage_kws   = ['cabinet', 'wardrobe', 'shelf', 'locker', 'bookcase', 'shelving', 'rack']
toilet_kws    = ['toilet', 'wc', 'lavatory']
sink_kws      = ['sink', 'basin', 'washbasin']
shower_kws    = ['shower', 'bath', 'tub']

gym_count     = sum(1 for n in names if any(kw in n for kw in gym_kws))
desk_count    = sum(1 for n in names if any(kw in n for kw in desk_kws) and 'bed' not in n and 'weight' not in n)
chair_count   = sum(1 for n in names if any(kw in n for kw in chair_kws))
lounge_count  = sum(1 for n in names if any(kw in n for kw in lounge_kws) and 'weight' not in n)
storage_count = sum(1 for n in names if any(kw in n for kw in storage_kws))
toilet_count  = sum(1 for n in names if any(kw in n for kw in toilet_kws))
sink_count    = sum(1 for n in names if any(kw in n for kw in sink_kws))
shower_count  = sum(1 for n in names if any(kw in n for kw in shower_kws))

# Calculate deltas from baseline
new_walls = max(0, data.get('wall_count', 0) - baseline.get('wall_count', 0))
new_rooms = max(0, data.get('room_count', 0) - baseline.get('room_count', 0))
new_labels = max(0, data.get('label_count', 0) - baseline.get('label_count', 0))
zone_identifiers = max(new_rooms, new_labels, len(data.get('room_names', [])))

if data.get('file_md5') and data.get('file_md5') != baseline.get('starter_md5'):
    data['file_changed'] = True
else:
    # Also check timestamp
    try:
        mtime = os.path.getmtime(sh3d_file)
        if mtime > task_start:
            data['file_changed'] = True
    except:
        pass

result = {
    'furniture_count': data.get('furniture_count', 0),
    'gym_count': gym_count,
    'desk_count': desk_count,
    'chair_count': chair_count,
    'lounge_count': lounge_count,
    'storage_count': storage_count,
    'toilet_count': toilet_count,
    'sink_count': sink_count,
    'shower_count': shower_count,
    'new_walls': new_walls,
    'zone_identifiers': zone_identifiers,
    'rooms_with_floor_color': data.get('rooms_with_floor_color', 0),
    'file_changed': data.get('file_changed', False),
    'render_found': render_found
}

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="