#!/bin/bash
echo "=== Exporting botanical_visitor_center results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="botanical_visitor_center"
SH3D_FILE="/home/ga/Documents/SweetHome3D/botanical_starter.sh3d"
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

# ── Step 5: Parse the .sh3d file ──────────────────────────────────────────────
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
        'window_count': 0,
        'room_count': 0,
        'room_names': [],
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
                # Count windows specifically (ignoring plain doors)
                if elem.get('doorOrWindow', '').lower() == 'true':
                    if any(kw in name for kw in ['window', 'glass', 'fenetre', 'pane', 'skylight']):
                        data['window_count'] += 1
                        
            elif tag == 'room':
                data['room_count'] += 1
                rname = (elem.get('name') or '').strip()
                if rname:
                    data['room_names'].append(rname.lower())
                
                # Check for floor color or floor texture attributes
                has_floor_color = elem.get('floorColor') is not None
                has_floor_texture = elem.get('floorTexture') is not None
                
                # Also check child elements for floorTexture just in case
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
    baseline = {'furniture_count': 0, 'starter_md5': None, 'wall_count': 0, 'room_count': 0, 'window_count': 0}

# Parse current file
data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorize furniture by domain-specific keywords
plant_kws  = ['plant', 'tree', 'flower', 'ficus', 'monstera', 'orchid', 'bush', 'shrub']
chair_kws  = ['chair', 'stool', 'seat']
bench_kws  = ['bench', 'pew', 'sofa'] # Allow sofas as alternative benches
table_kws  = ['table']
desk_kws   = ['desk', 'counter', 'reception', 'workstation', 'station']
shelf_kws  = ['shelf', 'shelving', 'rack', 'cabinet', 'bookcase', 'storage', 'cupboard', 'display']

plant_count  = sum(1 for n in names if any(kw in n for kw in plant_kws))
chair_count  = sum(1 for n in names if any(kw in n for kw in chair_kws))
bench_count  = sum(1 for n in names if any(kw in n for kw in bench_kws))
table_count  = sum(1 for n in names if any(kw in n for kw in table_kws))
desk_count   = sum(1 for n in names if any(kw in n for kw in desk_kws))
shelf_count  = sum(1 for n in names if any(kw in n for kw in shelf_kws))

# Calculate deltas from baseline
new_walls = max(0, data.get('wall_count', 0) - baseline.get('wall_count', 0))
new_rooms = max(0, data.get('room_count', 0) - baseline.get('room_count', 0))
new_windows = max(0, data.get('window_count', 0) - baseline.get('window_count', 0))

file_changed = False
if data.get('file_found') and data.get('file_md5') != baseline.get('starter_md5'):
    file_changed = True

result_payload = {
    'furniture_count': data.get('furniture_count', 0),
    'wall_count': data.get('wall_count', 0),
    'room_count': data.get('room_count', 0),
    'window_count': data.get('window_count', 0),
    'new_walls': new_walls,
    'new_rooms': new_rooms,
    'new_windows': new_windows,
    'room_names': data.get('room_names', []),
    'rooms_with_floor_color': data.get('rooms_with_floor_color', 0),
    'plant_count': plant_count,
    'chair_count': chair_count,
    'bench_count': bench_count,
    'table_count': table_count,
    'desk_count': desk_count,
    'shelf_count': shelf_count,
    'file_changed': file_changed,
    'error': data.get('error')
}

with open(result_path, 'w') as f:
    json.dump(result_payload, f, indent=2)

print(f"Extraction complete. Result saved to {result_path}")
PYEOF

echo "=== Export complete ==="