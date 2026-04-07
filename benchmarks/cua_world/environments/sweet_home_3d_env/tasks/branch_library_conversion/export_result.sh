#!/bin/bash
echo "=== Exporting branch_library_conversion results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="branch_library_conversion"
SH3D_FILE="/home/ga/Documents/SweetHome3D/branch_library_starter.sh3d"
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
        'room_count': 0,
        'room_names': [],
        'floor_colors': [],
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
                name = (elem.get('name') or '').lower().strip()
                data['furniture_names'].append(name)
            elif tag == 'room':
                data['room_count'] += 1
                rname = (elem.get('name') or '').strip()
                if rname:
                    data['room_names'].append(rname.lower())
                
                floor_color = elem.get('floorColor')
                floor_texture = None
                for child in elem:
                    child_tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                    if child_tag == 'floorTexture':
                        floor_texture = child.get('catalogId') or child.get('name') or 'texture'
                        break
                
                if floor_color:
                    data['floor_colors'].append(f"color_{floor_color}")
                elif floor_texture:
                    data['floor_colors'].append(f"texture_{floor_texture}")

            elif tag == 'label':
                ltext = (elem.get('text') or '').strip()
                if ltext:
                    data['label_count'] += 1
                    data['label_texts'].append(ltext.lower())

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

category_kws = {
    "shelves": ["shelf", "shelving", "bookcase", "bookshelf", "cabinet", "cupboard", "wardrobe", "storage", "rack", "étagère", "credenza"],
    "desks": ["desk", "counter", "station", "podium", "lectern"],
    "tables": ["table"],
    "chairs": ["chair", "stool", "seat", "armchair", "bench", "sofa"],
    "lamps": ["lamp", "light", "sconce", "chandelier", "lantern", "fixture"],
    "plants_decor": ["plant", "flower", "vase", "pot", "tree", "art", "picture", "frame", "sculpture", "rug", "clock", "mirror"]
}

counts = {k: 0 for k in category_kws}

for n in names:
    for cat in ["shelves", "desks", "tables", "chairs", "lamps", "plants_decor"]:
        if any(kw in n for kw in category_kws[cat]):
            counts[cat] += 1
            break

result = {
    'file_found': data['file_found'],
    'furniture_count': data['furniture_count'],
    'room_count': data['room_count'],
    'rooms_with_names': len(data['room_names']),
    'labels_count': data['label_count'],
    'distinct_floor_colors': len(set(data['floor_colors'])),
    'shelves': counts['shelves'],
    'desks': counts['desks'],
    'tables': counts['tables'],
    'chairs': counts['chairs'],
    'lamps': counts['lamps'],
    'plants_decor': counts['plants_decor'],
    'file_changed': data['file_md5'] != baseline.get('starter_md5') if data['file_md5'] else False,
    'current_md5': data['file_md5'],
    'baseline_md5': baseline.get('starter_md5')
}

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print("Export completed successfully. Result:")
print(json.dumps(result, indent=2))
PYEOF