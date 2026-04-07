#!/bin/bash
echo "=== Setting up airport_vip_lounge_design task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="airport_vip_lounge_design"
STARTER_SRC="/opt/sweethome3d_samples/SweetHome3DExample7.sh3d"
STARTER_DST="/home/ga/Documents/SweetHome3D/airport_lounge_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS="/tmp/${TASK_NAME}_start_ts"

# Clean stale artifacts
rm -f "$STARTER_DST" "$RESULT_JSON" "$BASELINE_JSON"
rm -f /home/ga/Desktop/lounge_render.png 2>/dev/null
[ -f "$STARTER_DST" ] && echo "ERROR: cleanup failed" && exit 1

# Record start time for verification
date +%s > "$START_TS"
echo "Task start timestamp: $(cat $START_TS)"

if [ ! -f "$STARTER_SRC" ]; then
    echo "ERROR: Source file not found: $STARTER_SRC"
    exit 1
fi

echo "Creating stripped VIP lounge starter from $STARTER_SRC ..."
python3 << 'PYEOF'
import zipfile, io, sys, json, hashlib, os
import xml.etree.ElementTree as ET

src = '/opt/sweethome3d_samples/SweetHome3DExample7.sh3d'
dst = '/home/ga/Documents/SweetHome3D/airport_lounge_starter.sh3d'
baseline_path = '/tmp/airport_vip_lounge_design_baseline.json'

try:
    with zipfile.ZipFile(src, 'r') as zf:
        namelist = zf.namelist()
        xml_name = next((n for n in ['Home.xml', 'Home', 'home.xml', 'home'] if n in namelist), None)
        if not xml_name:
            xml_name = next((n for n in namelist if n.endswith('.xml')), None)
        
        content = zf.read(xml_name)
        root = ET.fromstring(content)

        # Strip ALL furniture elements to provide a blank commercial shell
        def strip_furniture(element):
            to_remove = [child for child in element if child.tag.split('}')[-1] in ('pieceOfFurniture', 'furnitureGroup')]
            for child in to_remove:
                element.remove(child)
            for child in element:
                strip_furniture(child)

        strip_furniture(root)
        
        # Count structural elements preserved from the source file
        baseline_walls = sum(1 for _ in root.iter('wall'))
        baseline_rooms = sum(1 for _ in root.iter('room'))

        ET.register_namespace('', '')
        modified_xml = '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding='unicode')

        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as out_zf:
            for item in namelist:
                if item == xml_name:
                    out_zf.writestr(item, modified_xml.encode('utf-8'))
                else:
                    out_zf.writestr(item, zf.read(item))

    with open(dst, 'wb') as f:
        f.write(buf.getvalue())

    with open(dst, 'rb') as f:
        starter_md5 = hashlib.md5(f.read()).hexdigest()

    baseline = {
        'furniture_count': 0,
        'wall_count': baseline_walls,
        'room_count': baseline_rooms,
        'starter_md5': starter_md5
    }
    with open(baseline_path, 'w') as f:
        json.dump(baseline, f)

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

if [ ! -f "$STARTER_DST" ]; then
    echo "ERROR: Starter file was not created"
    exit 1
fi

chown ga:ga "$STARTER_DST" 2>/dev/null || true
chown ga:ga "$BASELINE_JSON" 2>/dev/null || true

# Launch Sweet Home 3D with the prepared starter plan
echo "Launching Sweet Home 3D..."
setup_sweet_home_3d_task "$STARTER_DST"

echo "=== airport_vip_lounge_design task setup complete ==="