#!/bin/bash
echo "=== Exporting photography_studio_conversion results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="photography_studio_conversion"
SH3D_FILE="/home/ga/Documents/SweetHome3D/photography_studio_starter.sh3d"
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

# ── Step 5: Search for 3D photo rendering files ──────────────────────────────
PHOTO_FOUND="false"
PHOTO_PATH=""
for IMG in /home/ga/Desktop/*.png /home/ga/Desktop/*.jpg /home/ga/*.png; do
    [ -f "$IMG" ] || continue
    # Ignore our own screenshots
    if [[ "$IMG" == *task_start_screenshot* ]] || [[ "$IMG" == *end_screenshot* ]]; then
        continue
    fi
    IMTIME=$(stat -c %Y "$IMG" 2>/dev/null || echo "0")
    if [ "$IMTIME" -gt "$TASK_START" ]; then
        echo "Found 3D photo candidate: $IMG (mtime=$IMTIME)"
        PHOTO_FOUND="true"
        PHOTO_PATH="$IMG"
        break
    fi
done
echo "3D photo found: $PHOTO_FOUND ($PHOTO_PATH)"

# ── Step 6: Parse the .sh3d file (walls, labels, distinct furniture zones) ──
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
                name = (elem.get('name') or '').lower().strip()
                data['furniture_names'].append(name)
            elif tag == 'wall':
                data['wall_count'] += 1
            elif tag == 'label':
                ltext = (elem.get('text') or '').strip()
                if ltext:
                    data['label_count'] += 1
                    data['label_texts'].append(ltext.lower())

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
    baseline = {'furniture_count': 0, 'starter_md5': None, 'wall_count': 0, 'label_count': 0}

# Parse current file
data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorise furniture by domain-specific keywords
desk_kws   = ['desk', 'table', 'workstation', 'counter', 'station', 'platform']
chair_kws  = ['chair', 'stool', 'seat', 'armchair', 'bench']
sofa_kws   = ['sofa', 'couch', 'loveseat', 'settee']
shelf_kws  = ['shelf', 'shelving', 'bookcase', 'bookshelf', 'cabinet', 'cupboard', 'wardrobe', 'storage', 'rack', 'closet']
lamp_kws   = ['lamp', 'light', 'lighting', 'fixture', 'sconce', 'chandelier']
decor_kws  = ['plant', 'flower', 'vase', 'art', 'picture', 'frame', 'mirror', 'rug', 'carpet']

desk_count  = sum(1 for n in names if any(kw in n for kw in desk_kws))
chair_count = sum(1 for n in names if any(kw in n for kw in chair_kws))
sofa_count  = sum(1 for n in names if any(kw in n for kw in sofa_kws))
shelf_count = sum(1 for n in names if any(kw in n for kw in shelf_kws))
lamp_count  = sum(1 for n in names if any(kw in n for kw in lamp_kws))
decor_count = sum(1 for n in names if any(kw in n for kw in decor_kws))

# Calculate deltas for walls and labels
new_walls = max(0, data.get('wall_count', 0) - baseline.get('wall_count', 0))
new_labels = max(0, data.get('label_count', 0) - baseline.get('label_count', 0))
file_changed = (data.get('file_md5') != baseline.get('starter_md5'))

result = {
    'file_found': data.get('file_found', False),
    'file_changed': file_changed,
    'furniture_count': data.get('furniture_count', 0),
    'desk_count': desk_count,
    'chair_count': chair_count,
    'sofa_count': sofa_count,
    'shelf_count': shelf_count,
    'lamp_count': lamp_count,
    'decor_count': decor_count,
    'new_walls': new_walls,
    'new_labels': new_labels,
    'photo_found': photo_found,
    'photo_path': photo_path,
    'label_texts': data.get('label_texts', [])
}

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print("Parsed result:")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="