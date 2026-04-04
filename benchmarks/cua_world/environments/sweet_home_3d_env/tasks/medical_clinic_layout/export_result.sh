#!/bin/bash
echo "=== Exporting medical_clinic_layout results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="medical_clinic_layout"
SH3D_FILE="/home/ga/Documents/SweetHome3D/medical_clinic_starter.sh3d"
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

# ── Step 4: Find the task .sh3d file (also search for saved-as copies) ─────────
TASK_START=$(cat "$START_TS_FILE" 2>/dev/null || echo "0")
FOUND_FILE=""

# Primary: the task's starter file (agent saves in-place)
if [ -f "$SH3D_FILE" ]; then
    FOUND_FILE="$SH3D_FILE"
fi

# Secondary: search for any newer .sh3d files created since task start
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
task_start = int('${TASK_START}' or '0')

def parse_sh3d(file_path):
    data = {
        'furniture_names': [],
        'furniture_count': 0,
        'room_count': 0,
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
            elif tag == 'room':
                data['room_count'] += 1
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
    baseline = {'furniture_count': 0, 'starter_md5': None}

# Parse current file
data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorise furniture by keyword
chair_kws   = ['chair', 'stool', 'bench', 'seat', 'armchair', 'sofa', 'settee', 'couch']
desk_kws    = ['desk', 'counter', 'reception', 'workstation', 'station', 'table']
bed_kws     = ['bed', 'exam', 'gurney', 'stretcher', 'cot', 'couch']
toilet_kws  = ['toilet', 'sink', 'basin', 'lavatory', 'wc', 'washbasin', 'lavabo']

chair_count   = sum(1 for n in names if any(kw in n for kw in chair_kws))
desk_count    = sum(1 for n in names if any(kw in n for kw in desk_kws))
bed_count     = sum(1 for n in names if any(kw in n for kw in bed_kws))
toilet_count  = sum(1 for n in names if any(kw in n for kw in toilet_kws))

# Distinct furniture types (unique keywords matched)
type_set = set()
for n in names:
    for kw in chair_kws + desk_kws + bed_kws + toilet_kws + ['lamp', 'light', 'shelf', 'cabinet', 'wardrobe', 'plant']:
        if kw in n:
            type_set.add(kw)
distinct_types = len(type_set)

result = {
    'furniture_count': data['furniture_count'],
    'room_count': data['room_count'],
    'wall_count': data['wall_count'],
    'chair_count': chair_count,
    'desk_count': desk_count,
    'bed_count': bed_count,
    'toilet_count': toilet_count,
    'distinct_types': distinct_types,
    'furniture_names_sample': names[:30],
    'file_found': data['file_found'],
    'file_md5': data.get('file_md5'),
    'baseline_md5': baseline.get('starter_md5'),
    'file_changed': data.get('file_md5') != baseline.get('starter_md5'),
    'error': data.get('error')
}

with open(result_path, 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== medical_clinic_layout export complete ==="
