#!/bin/bash
echo "=== Exporting community_makerspace_layout results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="community_makerspace_layout"
SH3D_FILE="/home/ga/Documents/SweetHome3D/makerspace_starter.sh3d"
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

# ── Step 5: Parse the .sh3d file and compare with baseline ────────────────────
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'

def parse_sh3d(file_path):
    data = {
        'furniture_names': [],
        'total_items_count': 0,
        'door_window_count': 0,
        'room_count': 0,
        'room_names': [],
        'rooms_with_floor_color': 0,
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
                data['total_items_count'] += 1
                name = (elem.get('name') or '').lower().strip()
                
                is_door_window = elem.get('doorOrWindow', '').lower() == 'true'
                if is_door_window:
                    data['door_window_count'] += 1
                else:
                    data['furniture_names'].append(name)
                    
            elif tag == 'room':
                data['room_count'] += 1
                rname = (elem.get('name') or '').strip()
                if rname:
                    data['room_names'].append(rname.lower())
                
                # Check for floorColor attribute or floorTexture child
                has_floor_color = elem.get('floorColor') is not None
                has_floor_texture = False
                for child in elem:
                    ctag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                    if ctag == 'floorTexture':
                        has_floor_texture = True
                        break
                if has_floor_color or has_floor_texture:
                    data['rooms_with_floor_color'] += 1
            
            elif tag == 'wall':
                data['wall_count'] += 1
            
            elif tag == 'label':
                data['label_count'] += 1
                ltext = (elem.get('text') or '').strip()
                if ltext:
                    data['label_texts'].append(ltext.lower())

    except Exception as e:
        data['error'] = str(e)

    return data

# Load baseline
try:
    with open(baseline_path) as f:
        baseline = json.load(f)
except Exception:
    baseline = {'wall_count': 0, 'room_count': 0, 'label_count': 0, 'door_window_count': 0, 'starter_md5': None}

# Parse current file
data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorise actual furniture by keyword
desk_kws   = ['desk', 'table', 'workstation', 'counter', 'bench', 'workbench']
chair_kws  = ['chair', 'stool', 'seat', 'armchair', 'sofa', 'couch']
shelf_kws  = ['shelf', 'shelving', 'bookcase', 'bookshelf', 'cabinet', 'cupboard', 'wardrobe', 'storage', 'rack', 'locker', 'chest']
lamp_kws   = ['lamp', 'light', 'sconce', 'spotlight', 'chandelier']
decor_kws  = ['plant', 'flower', 'vase', 'pot', 'painting', 'picture', 'frame', 'sculpture', 'art', 'rug', 'carpet']

desk_count  = sum(1 for n in names if any(kw in n for kw in desk_kws))
chair_count = sum(1 for n in names if any(kw in n for kw in chair_kws))
shelf_count = sum(1 for n in names if any(kw in n for kw in shelf_kws))
lamp_count  = sum(1 for n in names if any(kw in n for kw in lamp_kws))
decor_count = sum(1 for n in names if any(kw in n for kw in decor_kws))

# Calculate deltas from baseline
data['new_walls'] = max(0, data['wall_count'] - baseline.get('wall_count', 0))
data['new_doors'] = max(0, data['door_window_count'] - baseline.get('door_window_count', 0))

# Compile final result
result = {
    'file_found': data['file_found'],
    'file_changed': data['file_md5'] != baseline.get('starter_md5') if data['file_md5'] else False,
    'total_items_count': data['total_items_count'],
    'actual_furniture_count': len(names),
    
    'new_walls': data['new_walls'],
    'new_doors': data['new_doors'],
    'room_count': data['room_count'],
    'room_names': data['room_names'],
    'rooms_with_floor_color': data['rooms_with_floor_color'],
    'label_count': data['label_count'],
    'label_texts': data['label_texts'],
    
    'desk_count': desk_count,
    'chair_count': chair_count,
    'shelf_count': shelf_count,
    'lamp_count': lamp_count,
    'decor_count': decor_count
}

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="