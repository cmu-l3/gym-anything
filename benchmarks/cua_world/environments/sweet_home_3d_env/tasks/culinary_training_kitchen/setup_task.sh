#!/bin/bash
echo "=== Setting up culinary_training_kitchen task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="culinary_training_kitchen"
STARTER_SRC="/opt/sweethome3d_samples/SweetHome3DExample7.sh3d"
STARTER_DST="/home/ga/Documents/SweetHome3D/culinary_school_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS="/tmp/${TASK_NAME}_start_ts"

# ── Step 1: CLEAN ─────────────────────────────────────────────────────────────
echo "Cleaning stale artifacts..."
rm -f "$STARTER_DST"
rm -f "$RESULT_JSON"
rm -f "$BASELINE_JSON"
[ -f "$STARTER_DST" ] && echo "ERROR: cleanup failed" && exit 1

# ── Step 2: RECORD ────────────────────────────────────────────────────────────
date +%s > "$START_TS"
echo "Task start timestamp: $(cat $START_TS)"

# ── Step 3: SEED — create stripped starter .sh3d from existing sample ─────────
if [ ! -f "$STARTER_SRC" ]; then
    echo "ERROR: Source file not found: $STARTER_SRC"
    exit 1
fi

echo "Creating stripped culinary school starter from $STARTER_SRC ..."
python3 << 'PYEOF'
import zipfile, io, sys, json, hashlib, os
import xml.etree.ElementTree as ET

src = '/opt/sweethome3d_samples/SweetHome3DExample7.sh3d'
dst = '/home/ga/Documents/SweetHome3D/culinary_school_starter.sh3d'
baseline_path = '/tmp/culinary_training_kitchen_baseline.json'

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

        # Strip ALL furniture elements
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

    # Count baseline structural elements (walls, rooms, labels preserved from source)
    baseline_walls = 0
    baseline_rooms = 0
    baseline_labels = 0
    baseline_dims = 0
    for elem in root.iter():
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        if tag == 'wall':
            baseline_walls += 1
        elif tag == 'room':
            baseline_rooms += 1
        elif tag == 'label':
            baseline_labels += 1
        elif tag == 'dimensionLine':
            baseline_dims += 1

    baseline = {
        'furniture_count': 0,
        'furniture_names': [],
        'wall_count': baseline_walls,
        'room_count': baseline_rooms,
        'label_count': baseline_labels,
        'dimension_count': baseline_dims,
        'door_window_count': 0,
        'starter_md5': starter_md5,
        'starter_file': dst
    }
    with open(baseline_path, 'w') as f:
        json.dump(baseline, f, indent=2)

    print(f"Starter created: {dst} ({os.path.getsize(dst)} bytes)")
    print(f"Baseline furniture count: 0 (stripped)")
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

if [ ! -f "$STARTER_DST" ] || [ ! -s "$STARTER_DST" ]; then
    echo "ERROR: Starter file was not created at $STARTER_DST"
    exit 1
fi

echo "Starter file created: $STARTER_DST ($(stat -c%s "$STARTER_DST") bytes)"

chown ga:ga "$STARTER_DST" 2>/dev/null || true
chown ga:ga "$BASELINE_JSON" 2>/dev/null || true

# ── Step 4: LAUNCH ────────────────────────────────────────────────────────────
echo "Launching Sweet Home 3D with culinary school starter..."
setup_sweet_home_3d_task "$STARTER_DST"

echo "=== culinary_training_kitchen task setup complete ==="