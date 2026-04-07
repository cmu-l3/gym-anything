#!/bin/bash
echo "=== Exporting apartment_renovation_presentation results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="apartment_renovation_presentation"
SH3D_FILE="/home/ga/Documents/SweetHome3D/apartment_renovation_starter.sh3d"
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

# Check primary expected paths
for PRIMARY in "$SH3D_FILE" \
               "/home/ga/Documents/SweetHome3D/apartment_renovation_final.sh3d"; do
    if [ -f "$PRIMARY" ]; then
        FOUND_FILE="$PRIMARY"
    fi
done

# Scan for any newer .sh3d file (handles Save As to different name)
for CANDIDATE in /home/ga/Documents/SweetHome3D/*.sh3d /home/ga/Desktop/*.sh3d /home/ga/*.sh3d; do
    [ -f "$CANDIDATE" ] || continue
    FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
    if [ "$FMTIME" -gt "$TASK_START" ]; then
        echo "Found newer .sh3d: $CANDIDATE (mtime=$FMTIME vs task_start=$TASK_START)"
        FOUND_FILE="$CANDIDATE"
        break
    fi
done

echo "Using .sh3d file: $FOUND_FILE"

# ── Step 5: Search for 3D photo rendering files ──────────────────────────────
PHOTO_FOUND="False"
PHOTO_PATH=""
PHOTO_SIZE=0
for IMG in /home/ga/Desktop/renovation_render.png \
           /home/ga/Desktop/renovation_render.jpg \
           /home/ga/Desktop/*.png \
           /home/ga/Desktop/*.jpg \
           /home/ga/Documents/*.png \
           /home/ga/*.png; do
    [ -f "$IMG" ] || continue
    IMTIME=$(stat -c %Y "$IMG" 2>/dev/null || echo "0")
    if [ "$IMTIME" -gt "$TASK_START" ]; then
        IMSIZE=$(stat -c %s "$IMG" 2>/dev/null || echo "0")
        echo "Found 3D photo candidate: $IMG (mtime=$IMTIME, size=$IMSIZE)"
        PHOTO_FOUND="True"
        PHOTO_PATH="$IMG"
        PHOTO_SIZE="$IMSIZE"
        break
    fi
done
echo "3D photo found: $PHOTO_FOUND ($PHOTO_PATH, ${PHOTO_SIZE} bytes)"

# ── Step 6: Parse the .sh3d file ─────────────────────────────────────────────
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'
photo_found = ${PHOTO_FOUND}
photo_path = '${PHOTO_PATH}'
photo_size = ${PHOTO_SIZE}

def parse_sh3d(file_path):
    data = {
        'furniture_names': [],
        'furniture_count': 0,
        'door_window_count': 0,
        'room_count': 0,
        'room_names': [],
        'rooms_with_floor_color': 0,
        'walls_with_texture': 0,
        'wall_count': 0,
        'label_count': 0,
        'dimension_count': 0,
        'elevated_items': 0,
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

                # Check if this is a door or window
                if elem.get('doorOrWindow', '').lower() == 'true':
                    data['door_window_count'] += 1

                # Check for elevated items (wall-mounted: elevation > 20cm)
                try:
                    elev = float(elem.get('elevation', '0'))
                    if elev > 20:
                        data['elevated_items'] += 1
                except (ValueError, TypeError):
                    pass

            elif tag == 'room':
                data['room_count'] += 1
                rname = (elem.get('name') or '').strip()
                if rname:
                    data['room_names'].append(rname.lower())
                # Check for floor color or texture
                has_floor = elem.get('floorColor') is not None
                for child in elem:
                    child_tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                    if child_tag == 'floorTexture':
                        has_floor = True
                        break
                if has_floor:
                    data['rooms_with_floor_color'] += 1

            elif tag == 'wall':
                data['wall_count'] += 1
                # Check for wall textures or non-default wall colors
                has_wall_finish = False
                left_color = elem.get('leftSideColor')
                right_color = elem.get('rightSideColor')
                if left_color is not None or right_color is not None:
                    has_wall_finish = True
                for child in elem:
                    child_tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                    if child_tag in ('leftSideTexture', 'rightSideTexture'):
                        has_wall_finish = True
                        break
                if has_wall_finish:
                    data['walls_with_texture'] += 1

            elif tag == 'label':
                ltext = (elem.get('text') or '').strip()
                if ltext:
                    data['label_count'] += 1

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
    baseline = {'furniture_count': 0, 'starter_md5': None, 'room_count': 0, 'dimension_count': 0}

# Parse current file
data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Compute deltas from baseline
new_dimensions = max(0, data['dimension_count'] - baseline.get('dimension_count', 0))

# Categorise furniture by keywords (first match wins)
category_order = ['doors', 'beds', 'bath_fixtures', 'kitchen_appliances', 'sinks',
                  'desks', 'shelves', 'sofas', 'tables', 'chairs', 'lamps', 'decor']

category_kws = {
    'doors': ['door', 'window'],
    'beds': ['bed', 'nightstand', 'night stand'],
    'bath_fixtures': ['bathtub', 'bath tub', 'toilet', 'shower', 'bidet'],
    'kitchen_appliances': ['oven', 'cooker', 'fridge', 'refrigerator', 'freezer',
                           'dishwasher', 'microwave', 'washer', 'dryer'],
    'sinks': ['sink', 'basin', 'washbasin'],
    'desks': ['desk', 'counter', 'workstation', 'station'],
    'shelves': ['shelf', 'shelving', 'bookcase', 'bookshelf', 'cabinet', 'cupboard',
                'wardrobe', 'storage', 'rack', 'dresser', 'credenza'],
    'sofas': ['sofa', 'couch', 'settee', 'loveseat', 'armchair'],
    'tables': ['table'],
    'chairs': ['chair', 'stool', 'seat', 'bench'],
    'lamps': ['lamp', 'light', 'sconce', 'chandelier', 'lantern', 'fixture',
              'pendant', 'spotlight', 'uplight', 'halogen'],
    'decor': ['plant', 'flower', 'vase', 'tree', 'pot', 'art', 'picture', 'frame',
              'sculpture', 'mirror', 'rug', 'clock', 'ornament', 'tv', 'television',
              'computer', 'laptop', 'monitor', 'mannequin']
}

counts = {k: 0 for k in category_kws}
for n in names:
    for cat in category_order:
        if any(kw in n for kw in category_kws[cat]):
            counts[cat] += 1
            break

# Count distinct furniture categories present (excluding doors)
categories_with_items = sum(1 for cat in category_order if cat != 'doors' and counts[cat] > 0)

result = {
    'file_found': data['file_found'],
    'furniture_count': data['furniture_count'],
    'door_window_count': data['door_window_count'],
    'room_count': data['room_count'],
    'room_names': data.get('room_names', []),
    'rooms_with_floor_color': data['rooms_with_floor_color'],
    'walls_with_texture': data['walls_with_texture'],
    'wall_count': data['wall_count'],
    'dimension_count': data['dimension_count'],
    'new_dimensions': new_dimensions,
    'elevated_items': data['elevated_items'],
    'beds': counts['beds'],
    'bath_fixtures': counts['bath_fixtures'],
    'kitchen_appliances': counts['kitchen_appliances'],
    'sinks': counts['sinks'],
    'desks': counts['desks'],
    'shelves': counts['shelves'],
    'sofas': counts['sofas'],
    'tables': counts['tables'],
    'chairs': counts['chairs'],
    'lamps': counts['lamps'],
    'decor': counts['decor'],
    'categories_with_items': categories_with_items,
    'photo_found': photo_found,
    'photo_path': photo_path,
    'photo_size': photo_size,
    'furniture_names_sample': names[:50],
    'file_found': data['file_found'],
    'file_md5': data.get('file_md5'),
    'baseline_md5': baseline.get('starter_md5'),
    'file_changed': data.get('file_md5') != baseline.get('starter_md5'),
    'error': data.get('error')
}

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print("Export completed successfully. Result:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== apartment_renovation_presentation export complete ==="
