#!/bin/bash
echo "=== Exporting gallery_exhibition_layout results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="gallery_exhibition_layout"
SH3D_FILE="/home/ga/Documents/SweetHome3D/gallery_exhibition_starter.sh3d"
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

# Detect newly created copies if agent used "Save As"
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

# ── Step 5: Parse the .sh3d file to extract metrics ───────────────────────────
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
        'rooms_with_floor_color': 0,
        'wall_count': 0,
        'label_count': 0,
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
                
                # Check for floor styling (attribute or child node)
                has_color = elem.get('floorColor') is not None
                has_texture = False
                for child in elem:
                    ctag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                    if ctag == 'floorTexture':
                        has_texture = True
                        break
                if has_color or has_texture:
                    data['rooms_with_floor_color'] += 1
                    
            elif tag == 'wall':
                data['wall_count'] += 1
            elif tag == 'label':
                ltext = (elem.get('text') or '').strip()
                if len(ltext) > 0:  # Must actually contain text
                    data['label_count'] += 1

        data['furniture_count'] = len(data['furniture_names'])

    except Exception as e:
        data['error'] = str(e)

    return data

# Load baseline properties
baseline = {}
try:
    with open(baseline_path) as f:
        baseline = json.load(f)
except Exception:
    baseline = {'furniture_count': 0, 'starter_md5': None, 'wall_count': 0, 'room_count': 0, 'label_count': 0}

# Parse modified file
data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorize furniture based on task specifications
display_kws = ['table', 'shelf', 'shelving', 'bookcase', 'bookshelf', 'cabinet', 'cupboard', 'pedestal', 'counter', 'rack', 'console', 'stand', 'display']
seating_kws = ['chair', 'bench', 'sofa', 'stool', 'seat', 'armchair', 'settee', 'couch', 'ottoman']
lighting_kws = ['lamp', 'light', 'chandelier', 'sconce', 'lantern', 'spotlight']
decor_kws = ['plant', 'flower', 'vase', 'pot', 'fern', 'tree', 'art', 'sculpture', 'frame', 'picture', 'painting', 'ornament']

data['display_count'] = sum(1 for n in names if any(kw in n for kw in display_kws))
data['seating_count'] = sum(1 for n in names if any(kw in n for kw in seating_kws))
data['lighting_count'] = sum(1 for n in names if any(kw in n for kw in lighting_kws))
data['decor_count'] = sum(1 for n in names if any(kw in n for kw in decor_kws))

# Calculate distinct types diversity
types_found = set()
for kw in display_kws + seating_kws + lighting_kws + decor_kws:
    if any(kw in n for n in names):
        types_found.add(kw)
data['distinct_types'] = len(types_found)

# Calculate Deltas (Anti-gaming bounds)
data['new_walls'] = max(0, data.get('wall_count', 0) - baseline.get('wall_count', 0))
data['new_labels'] = max(0, data.get('label_count', 0) - baseline.get('label_count', 0))
data['file_changed'] = data.get('file_md5') != baseline.get('starter_md5') if data.get('file_md5') else False

# Write combined results securely to JSON
with open(result_path, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Results successfully saved to {result_path}")
PYEOF

chmod 666 "$RESULT_JSON" 2>/dev/null || true
echo "=== Export Complete ==="