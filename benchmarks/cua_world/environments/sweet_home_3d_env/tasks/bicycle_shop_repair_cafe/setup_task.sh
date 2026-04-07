#!/bin/bash
echo "=== Setting up bicycle_shop_repair_cafe task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="bicycle_shop_repair_cafe"
STARTER_SRC="/opt/sweethome3d_samples/SweetHome3DExample7.sh3d"
STARTER_DST="/home/ga/Documents/SweetHome3D/bike_shop_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS="/tmp/${TASK_NAME}_start_ts"

echo "Cleaning stale artifacts..."
rm -f "$STARTER_DST" "/home/ga/Documents/SweetHome3D/bicycle_shop_result.sh3d"
rm -f "$RESULT_JSON" "$BASELINE_JSON"

date +%s > "$START_TS"
echo "Task start timestamp: $(cat $START_TS)"

if [ ! -f "$STARTER_SRC" ]; then
    echo "ERROR: Source file not found: $STARTER_SRC"
    exit 1
fi

echo "Creating stripped starter from $STARTER_SRC ..."
python3 << 'PYEOF'
import zipfile, io, sys, json, hashlib, os
import xml.etree.ElementTree as ET

src = '/opt/sweethome3d_samples/SweetHome3DExample7.sh3d'
dst = '/home/ga/Documents/SweetHome3D/bike_shop_starter.sh3d'
baseline_path = '/tmp/bicycle_shop_repair_cafe_baseline.json'

try:
    with zipfile.ZipFile(src, 'r') as zf:
        namelist = zf.namelist()
        xml_name = next((n for n in ['Home.xml', 'Home', 'home.xml', 'home'] if n in namelist), None)
        if xml_name is None:
            xml_name = next((n for n in namelist if n.endswith('.xml')), None)
        if xml_name is None:
            print("ERROR: no XML found in source .sh3d", file=sys.stderr)
            sys.exit(1)

        content = zf.read(xml_name)
        root = ET.fromstring(content)

        # Strip all furniture, rooms, labels, and dimensions to provide a clean shell
        def strip_elements(element, tags_to_remove):
            to_remove = []
            for child in element:
                ctag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if ctag in tags_to_remove:
                    to_remove.append(child)
                else:
                    strip_elements(child, tags_to_remove)
            for child in to_remove:
                element.remove(child)

        strip_elements(root, ['pieceOfFurniture', 'furnitureGroup', 'room', 'label', 'dimensionLine'])

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

    baseline_walls = sum(1 for elem in root.iter() if (elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag) == 'wall')

    baseline = {
        'furniture_count': 0,
        'wall_count': baseline_walls,
        'room_count': 0,
        'label_count': 0,
        'dimension_count': 0,
        'door_window_count': 0,
        'starter_md5': starter_md5,
        'starter_file': dst
    }
    with open(baseline_path, 'w') as f:
        json.dump(baseline, f, indent=2)

    print(f"Starter created: {dst} ({os.path.getsize(dst)} bytes)")
    print(f"Starter MD5: {starter_md5}")

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

chown ga:ga "$STARTER_DST" "$BASELINE_JSON" 2>/dev/null || true

echo "Launching Sweet Home 3D with starter file..."
setup_sweet_home_3d_task "$STARTER_DST"

echo "=== bicycle_shop_repair_cafe task setup complete ==="