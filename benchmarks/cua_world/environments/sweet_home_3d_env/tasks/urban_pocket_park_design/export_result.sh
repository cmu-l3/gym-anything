#!/bin/bash
echo "=== Exporting urban_pocket_park_design results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="urban_pocket_park_design"
SH3D_FILE="/home/ga/Documents/SweetHome3D/pocket_park_final.sh3d"
RENDER_FILE="/home/ga/Documents/SweetHome3D/park_presentation.png"
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
    echo "Sweet Home 3D window found, triggering save..."
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

# Check primary required output path
if [ -f "$SH3D_FILE" ]; then
    FOUND_FILE="$SH3D_FILE"
else
    # Fallback search for any recently modified .sh3d file
    for CANDIDATE in /home/ga/Documents/SweetHome3D/*.sh3d /home/ga/Desktop/*.sh3d /home/ga/*.sh3d; do
        [ -f "$CANDIDATE" ] || continue
        FMTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
        if [ "$FMTIME" -gt "$TASK_START" ]; then
            FOUND_FILE="$CANDIDATE"
            break
        fi
    done
fi

echo "Using .sh3d file: $FOUND_FILE"

# 5. Check for Presentation Render image
PHOTO_FOUND="false"
PHOTO_PATH=""
if [ -f "$RENDER_FILE" ]; then
    PTIME=$(stat -c %Y "$RENDER_FILE" 2>/dev/null || echo "0")
    if [ "$PTIME" -gt "$TASK_START" ]; then
        PHOTO_FOUND="true"
        PHOTO_PATH="$RENDER_FILE"
    fi
else
    # Fallback search
    for IMG in /home/ga/Desktop/*.png /home/ga/Documents/*.png /home/ga/Documents/SweetHome3D/*.png; do
        [ -f "$IMG" ] || continue
        PTIME=$(stat -c %Y "$IMG" 2>/dev/null || echo "0")
        if [ "$PTIME" -gt "$TASK_START" ]; then
            PHOTO_FOUND="true"
            PHOTO_PATH="$IMG"
            break
        fi
    done
fi

echo "Photo found: $PHOTO_FOUND ($PHOTO_PATH)"

# 6. Parse the .sh3d file
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'
photo_found = ${PHOTO_FOUND}
photo_path = '${PHOTO_PATH}'

def parse_sh3d(file_path):
    data = {
        'furniture_names': [],
        'furniture_count': 0,
        'room_count': 0,
        'room_names': [],
        'rooms_with_floor_color': 0,
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
            elif tag == 'room':
                data['room_count'] += 1
                rname = (elem.get('name') or '').strip()
                if rname:
                    data['room_names'].append(rname.lower())
                
                # Check for color or texture to define zones
                has_floor_color = elem.get('floorColor') is not None
                has_floor_texture = False
                for child in elem:
                    child_tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                    if child_tag == 'floorTexture':
                        has_floor_texture = True
                        break
                if has_floor_color or has_floor_texture:
                    data['rooms_with_floor_color'] += 1
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
    baseline = {'furniture_count': 0, 'starter_md5': None}

data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorise objects
veg_kws = ['tree', 'plant', 'bush', 'flower', 'hedge', 'grass', 'palm', 'shrub', 'ivy', 'fern']
seat_kws = ['bench', 'chair', 'seat', 'stool']
light_kws = ['light', 'lamp', 'lantern', 'streetlight', 'post', 'sconce']

veg_count = sum(1 for n in names if any(kw in n for kw in veg_kws))
seat_count = sum(1 for n in names if any(kw in n for kw in seat_kws))
light_count = sum(1 for n in names if any(kw in n for kw in light_kws))

file_changed = False
if data.get('file_found') and data.get('file_md5') != baseline.get('starter_md5'):
    file_changed = True

result = {
    'file_found': data.get('file_found'),
    'file_changed': file_changed,
    'furniture_count': data.get('furniture_count', 0),
    'room_count': data.get('room_count', 0),
    'room_names': data.get('room_names', []),
    'rooms_with_floor_color': data.get('rooms_with_floor_color', 0),
    'dimension_count': data.get('dimension_count', 0),
    'veg_count': veg_count,
    'seat_count': seat_count,
    'light_count': light_count,
    'photo_found': photo_found,
    'photo_path': photo_path
}

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="