#!/bin/bash
echo "=== Setting up blood_donation_center_layout task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="blood_donation_center_layout"
STARTER_SRC="/opt/sweethome3d_samples/SweetHome3DExample.sh3d"
STARTER_DST="/home/ga/Documents/SweetHome3D/blood_donation_center_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS="/tmp/${TASK_NAME}_start_ts"

echo "Cleaning stale artifacts..."
rm -f "$STARTER_DST" "$RESULT_JSON" "$BASELINE_JSON"

date +%s > "$START_TS"

if [ ! -f "$STARTER_SRC" ]; then
    echo "ERROR: Source file not found: $STARTER_SRC"
    exit 1
fi

echo "Creating stripped starter from $STARTER_SRC ..."
python3 << 'PYEOF'
import zipfile, io, sys, json, hashlib, os
import xml.etree.ElementTree as ET

src = '/opt/sweethome3d_samples/SweetHome3DExample.sh3d'
dst = '/home/ga/Documents/SweetHome3D/blood_donation_center_starter.sh3d'
baseline_path = '/tmp/blood_donation_center_layout_baseline.json'

try:
    with zipfile.ZipFile(src, 'r') as zf:
        namelist = zf.namelist()
        xml_name = next((n for n in ['Home.xml', 'Home', 'home.xml', 'home'] if n in namelist), None)
        if not xml_name:
            xml_name = next((n for n in namelist if n.endswith('.xml')), None)
        
        content = zf.read(xml_name)
        root = ET.fromstring(content)

        def strip_furniture(element):
            to_remove = []
            for child in element:
                ctag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if ctag in ('pieceOfFurniture', 'furnitureGroup'):
                    to_remove.append(child)
                else:
                    strip_furniture(child)
            for child in to_remove:
                element.remove(child)

        strip_furniture(root)

        ET.register_namespace('', '')
        modified_xml = ET.tostring(root, encoding='unicode')
        modified_xml = '<?xml version="1.0" encoding="UTF-8"?>\n' + modified_xml

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

    baseline_walls = 0
    baseline_rooms = 0
    baseline_dims = 0
    for elem in root.iter():
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        if tag == 'wall':
            baseline_walls += 1
        elif tag == 'room':
            baseline_rooms += 1
        elif tag == 'dimensionLine':
            baseline_dims += 1

    baseline = {
        'furniture_count': 0,
        'wall_count': baseline_walls,
        'room_count': baseline_rooms,
        'dimension_count': baseline_dims,
        'door_window_count': 0,
        'starter_md5': starter_md5
    }
    with open(baseline_path, 'w') as f:
        json.dump(baseline, f)

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

chown ga:ga "$STARTER_DST" "$BASELINE_JSON" 2>/dev/null || true

setup_sweet_home_3d_task "$STARTER_DST"
echo "=== Setup complete ==="