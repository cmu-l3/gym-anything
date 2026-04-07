#!/bin/bash
echo "=== Setting up auto_repair_shop_layout task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="auto_repair_shop_layout"
STARTER_SRC="/opt/sweethome3d_samples/SweetHome3DExample.sh3d"
STARTER_DST="/home/ga/Documents/SweetHome3D/auto_repair_shop_starter.sh3d"
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

# 3. Create stripped starter .sh3d
if [ ! -f "$STARTER_SRC" ]; then
    echo "ERROR: Source file not found: $STARTER_SRC"
    exit 1
fi

echo "Creating empty 20x10m commercial shell from $STARTER_SRC ..."
python3 << 'PYEOF'
import zipfile, io, sys, json, hashlib, os
import xml.etree.ElementTree as ET

src = '/opt/sweethome3d_samples/SweetHome3DExample.sh3d'
dst = '/home/ga/Documents/SweetHome3D/auto_repair_shop_starter.sh3d'
baseline_path = '/tmp/auto_repair_shop_layout_baseline.json'

try:
    with zipfile.ZipFile(src, 'r') as zf:
        namelist = zf.namelist()

        xml_name = next((n for n in namelist if n.lower() == 'home.xml'), None)
        if not xml_name:
            xml_name = next((n for n in namelist if n.endswith('.xml')), None)
        if not xml_name:
            print("ERROR: no XML found in source .sh3d", file=sys.stderr)
            sys.exit(1)

        content = zf.read(xml_name)
        root = ET.fromstring(content)

        # Strip ALL existing walls, furniture, rooms, labels, dimensions
        to_remove = []
        for child in root:
            ctag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
            if ctag in ('pieceOfFurniture', 'furnitureGroup', 'room', 'label', 'dimensionLine', 'wall'):
                to_remove.append(child)
        for child in to_remove:
            root.remove(child)

        # Build a 20m x 10m exterior shell (Sweet Home 3D coordinates are in cm)
        # 2000cm x 1000cm
        ET.SubElement(root, 'wall', {'id': 'ext_w1', 'xStart': '0', 'yStart': '0', 'xEnd': '2000', 'yEnd': '0', 'thickness': '20', 'height': '350'})
        ET.SubElement(root, 'wall', {'id': 'ext_w2', 'xStart': '2000', 'yStart': '0', 'xEnd': '2000', 'yEnd': '1000', 'thickness': '20', 'height': '350'})
        ET.SubElement(root, 'wall', {'id': 'ext_w3', 'xStart': '2000', 'yStart': '1000', 'xEnd': '0', 'yEnd': '1000', 'thickness': '20', 'height': '350'})
        ET.SubElement(root, 'wall', {'id': 'ext_w4', 'xStart': '0', 'yStart': '1000', 'xEnd': '0', 'yEnd': '0', 'thickness': '20', 'height': '350'})

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
        'room_count': 0,
        'label_count': 0,
        'door_window_count': 0,
        'starter_md5': starter_md5,
        'starter_file': dst
    }
    with open(baseline_path, 'w') as f:
        json.dump(baseline, f, indent=2)

    print(f"Starter created: {dst} ({os.path.getsize(dst)} bytes)")
    print(f"Baseline wall count: 4 (exterior shell)")
    print(f"Starter MD5: {starter_md5}")

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    import traceback; traceback.print_exc()
    sys.exit(1)
PYEOF

if [ ! -f "$STARTER_DST" ]; then
    echo "ERROR: Starter file was not created"
    exit 1
fi

chown ga:ga "$STARTER_DST" 2>/dev/null || true
chown ga:ga "$BASELINE_JSON" 2>/dev/null || true

# 4. Launch Sweet Home 3D
echo "Launching Sweet Home 3D..."
setup_sweet_home_3d_task "$STARTER_DST"

echo "=== auto_repair_shop_layout task setup complete ==="