#!/bin/bash
echo "=== Setting up public_aquarium_visitor_center task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="public_aquarium_visitor_center"
STARTER_SRC="/opt/sweethome3d_samples/SweetHome3DExample7.sh3d"
STARTER_DST="/home/ga/Documents/SweetHome3D/aquarium_shell_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS="/tmp/${TASK_NAME}_start_ts"

# Clean stale artifacts
echo "Cleaning stale artifacts..."
rm -f "$STARTER_DST" "$RESULT_JSON" "$BASELINE_JSON"
[ -f "$STARTER_DST" ] && echo "ERROR: cleanup failed" && exit 1

# Record start time
date +%s > "$START_TS"
echo "Task start timestamp: $(cat $START_TS)"

# Create stripped starter .sh3d from existing sample
if [ ! -f "$STARTER_SRC" ]; then
    echo "ERROR: Source file not found: $STARTER_SRC"
    exit 1
fi

echo "Creating stripped aquarium shell starter from $STARTER_SRC ..."
python3 << 'PYEOF'
import zipfile, io, sys, json, hashlib, os
import xml.etree.ElementTree as ET

src = '/opt/sweethome3d_samples/SweetHome3DExample7.sh3d'
dst = '/home/ga/Documents/SweetHome3D/aquarium_shell_starter.sh3d'
baseline_path = '/tmp/public_aquarium_visitor_center_baseline.json'

try:
    with zipfile.ZipFile(src, 'r') as zf:
        namelist = zf.namelist()

        xml_name = next((c for c in ['Home.xml', 'Home', 'home.xml', 'home'] if c in namelist), None)
        if not xml_name:
            xml_name = next((n for n in namelist if n.endswith('.xml')), None)
        if not xml_name:
            print("ERROR: no XML found in source .sh3d", file=sys.stderr)
            sys.exit(1)

        content = zf.read(xml_name)
        root = ET.fromstring(content)

        def strip_selected(element):
            to_remove = []
            for child in element:
                ctag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                if ctag == 'pieceOfFurniture':
                    # Keep doors and windows, strip other furniture
                    if child.get('doorOrWindow', '').lower() != 'true':
                        to_remove.append(child)
                elif ctag in ('furnitureGroup', 'polyline', 'label', 'room'):
                    to_remove.append(child)
                else:
                    strip_selected(child)
            for child in to_remove:
                element.remove(child)

        strip_selected(root)

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

    baseline_walls = sum(1 for elem in root.iter() if (elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag) == 'wall')

    baseline = {
        'furniture_count': 0,
        'wall_count': baseline_walls,
        'room_count': 0,
        'label_count': 0,
        'polyline_count': 0,
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

# Launch Sweet Home 3D
echo "Launching Sweet Home 3D with aquarium shell starter..."
setup_sweet_home_3d_task "$STARTER_DST"

echo "=== public_aquarium_visitor_center task setup complete ==="