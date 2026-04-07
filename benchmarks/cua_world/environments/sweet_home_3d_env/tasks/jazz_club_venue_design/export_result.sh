#!/bin/bash
echo "=== Exporting jazz_club_venue_design results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="jazz_club_venue_design"
SH3D_FILE="/home/ga/Documents/SweetHome3D/jazz_club_project.sh3d"
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
        FOUND_FILE="$CANDIDATE"
        break
    fi
done

echo "Using .sh3d file: $FOUND_FILE"

# ── Step 5: Search for 3D photo rendering ─────────────────────────────────────
PHOTO_PATH="/home/ga/Desktop/jazz_club_render.png"
PHOTO_FOUND="false"
PHOTO_SIZE=0

if [ -f "$PHOTO_PATH" ]; then
    PHOTO_FOUND="true"
    PHOTO_SIZE=$(stat -c %s "$PHOTO_PATH" 2>/dev/null || echo "0")
    echo "3D photo found at expected path: $PHOTO_PATH (Size: $PHOTO_SIZE bytes)"
else
    # Fallback search if saved slightly elsewhere
    for IMG in /home/ga/Desktop/*.png /home/ga/Desktop/*.jpg /home/ga/Documents/*.png /home/ga/*.png; do
        [ -f "$IMG" ] || continue
        IMTIME=$(stat -c %Y "$IMG" 2>/dev/null || echo "0")
        if [ "$IMTIME" -gt "$TASK_START" ]; then
            PHOTO_FOUND="true"
            PHOTO_SIZE=$(stat -c %s "$IMG" 2>/dev/null || echo "0")
            echo "3D photo found at fallback path: $IMG (Size: $PHOTO_SIZE bytes)"
            break
        fi
    done
fi

# ── Step 6: Parse the .sh3d file ─────────────────────────────────────────────
python3 << PYEOF
import zipfile, json, hashlib, os, sys
import xml.etree.ElementTree as ET

sh3d_file = '${FOUND_FILE}'
result_path = '${RESULT_JSON}'
baseline_path = '${BASELINE_JSON}'

def parse_sh3d(file_path):
    data = {
        'furniture_names': [],
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
            xml_name = next((name for name in ['Home.xml', 'Home', 'home.xml', 'home'] if name in namelist), None)
            if xml_name is None:
                xml_name = next((n for n in namelist if n.endswith('.xml')), None)
            
            if xml_name is None:
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
                
                # Check floor treatments
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

    except Exception as e:
        data['error'] = str(e)

    return data

baseline = {}
try:
    with open(baseline_path) as f:
        baseline = json.load(f)
except Exception:
    baseline = {'wall_count': 0, 'room_count': 0, 'starter_md5': None}

data = parse_sh3d(sh3d_file)
names = data.get('furniture_names', [])

# Categorize furniture by domain-specific keywords
piano_kws  = ['piano', 'keyboard', 'synthesizer']
sofa_kws   = ['sofa', 'couch', 'settee', 'armchair']
chair_kws  = ['chair', 'stool', 'seat', 'bench']
table_kws  = ['table']
desk_kws   = ['desk', 'counter', 'workstation', 'bar']
toilet_kws = ['toilet', 'wc', 'lavatory', 'bidet']
sink_kws   = ['sink', 'basin', 'washbasin']

out = {
    'furniture_count': len(names),
    'piano_count': sum(1 for n in names if any(kw in n for kw in piano_kws)),
    'sofa_count': sum(1 for n in names if any(kw in n for kw in sofa_kws)),
    'chair_count': sum(1 for n in names if any(kw in n for kw in chair_kws)),
    'table_count': sum(1 for n in names if any(kw in n for kw in table_kws)),
    'desk_count': sum(1 for n in names if any(kw in n for kw in desk_kws)),
    'toilet_count': sum(1 for n in names if any(kw in n for kw in toilet_kws)),
    'sink_count': sum(1 for n in names if any(kw in n for kw in sink_kws)),
    'new_walls': max(0, data['wall_count'] - baseline.get('wall_count', 0)),
    'new_rooms': max(0, data['room_count'] - baseline.get('room_count', 0)),
    'room_names': data['room_names'],
    'rooms_with_floor_color': data['rooms_with_floor_color'],
    'file_changed': data['file_md5'] != baseline.get('starter_md5') if data['file_md5'] else False,
    'photo_found': ${PHOTO_FOUND},
    'photo_size': ${PHOTO_SIZE}
}

with open(result_path, 'w') as f:
    json.dump(out, f, indent=2)
PYEOF

chmod 644 "$RESULT_JSON" 2>/dev/null || true
echo "=== Export Complete ==="