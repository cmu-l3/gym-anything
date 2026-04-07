#!/bin/bash
echo "=== Setting up luxury_train_carriage_layout task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="luxury_train_carriage_layout"
STARTER_SRC="/opt/sweethome3d_samples/userGuideExample.sh3d"
STARTER_DST="/home/ga/Documents/SweetHome3D/train_carriage_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS="/tmp/${TASK_NAME}_start_ts"

# 1. Clean stale artifacts
echo "Cleaning stale artifacts..."
rm -f "$STARTER_DST" "$RESULT_JSON" "$BASELINE_JSON"
[ -f "$STARTER_DST" ] && echo "ERROR: cleanup failed" && exit 1

# 2. Record start time
date +%s > "$START_TS"
echo "Task start timestamp: $(cat $START_TS)"

# 3. Create starter .sh3d file with custom 25m x 3.5m shell walls
if [ ! -f "$STARTER_SRC" ]; then
    echo "ERROR: Source file not found: $STARTER_SRC"
    exit 1
fi

echo "Generating 25x3.5m train carriage shell from $STARTER_SRC ..."
python3 << 'PYEOF'
import zipfile, io, sys, json, hashlib, os
import xml.etree.ElementTree as ET

src = '/opt/sweethome3d_samples/userGuideExample.sh3d'
dst = '/home/ga/Documents/SweetHome3D/train_carriage_starter.sh3d'
baseline_path = '/tmp/luxury_train_carriage_layout_baseline.json'

try:
    with zipfile.ZipFile(src, 'r') as zf:
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
            print("ERROR: no XML found in source .sh3d", file=sys.stderr)
            sys.exit(1)

        content = zf.read(xml_name)
        root = ET.fromstring(content)

        # Remove all existing components completely
        to_remove = []
        for child in root:
            tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
            if tag in ('pieceOfFurniture', 'furnitureGroup', 'wall', 'room', 'label', 'dimensionLine', 'polyline', 'doorOrWindow'):
                to_remove.append(child)
        for child in to_remove:
            root.remove(child)

        # Add exactly 4 walls for 2500x350 cm shell (thickness 15, height 250)
        walls = [
            {'id': 'w1', 'xStart': '0', 'yStart': '0', 'xEnd': '2500', 'yEnd': '0', 'thickness': '15', 'height': '250'},
            {'id': 'w2', 'xStart': '2500', 'yStart': '0', 'xEnd': '2500', 'yEnd': '350', 'thickness': '15', 'height': '250'},
            {'id': 'w3', 'xStart': '2500', 'yStart': '350', 'xEnd': '0', 'yEnd': '350', 'thickness': '15', 'height': '250'},
            {'id': 'w4', 'xStart': '0', 'yStart': '350', 'xEnd': '0', 'yEnd': '0', 'thickness': '15', 'height': '250'}
        ]
        
        for w in walls:
            ET.SubElement(root, 'wall', w)

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

    baseline = {
        'furniture_count': 0,
        'wall_count': 4,
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
    import traceback; traceback.print_exc()
    sys.exit(1)
PYEOF

PYEXIT=$?
if [ $PYEXIT -ne 0 ]; then
    echo "ERROR: Failed to create starter .sh3d file"
    exit 1
fi

chown ga:ga "$STARTER_DST" 2>/dev/null || true
chown ga:ga "$BASELINE_JSON" 2>/dev/null || true

# 4. Launch Sweet Home 3D
echo "Launching Sweet Home 3D with train carriage starter..."
setup_sweet_home_3d_task "$STARTER_DST"

echo "=== luxury_train_carriage_layout task setup complete ==="