#!/bin/bash
echo "=== Setting up fire_station_renovation task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fire_station_renovation"
STARTER_SRC="/opt/sweethome3d_samples/SweetHome3DExample.sh3d"
STARTER_DST="/home/ga/Documents/SweetHome3D/fire_station_starter.sh3d"
RESULT_DST="/home/ga/Documents/SweetHome3D/fire_station_result.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS="/tmp/${TASK_NAME}_start_ts"

# ── Step 1: CLEAN ─────────────────────────────────────────────────────────────
echo "Cleaning stale artifacts..."
rm -f "$STARTER_DST" "$RESULT_DST" "$RESULT_JSON" "$BASELINE_JSON"
[ -f "$STARTER_DST" ] && echo "ERROR: cleanup failed" && exit 1

# ── Step 2: RECORD ────────────────────────────────────────────────────────────
date +%s > "$START_TS"
echo "Task start timestamp: $(cat $START_TS)"

# ── Step 3: SEED — create stripped starter .sh3d from existing sample ─────────
if [ ! -f "$STARTER_SRC" ]; then
    echo "ERROR: Source file not found: $STARTER_SRC"
    exit 1
fi

echo "Creating stripped fire station starter from $STARTER_SRC ..."
python3 << 'PYEOF'
import zipfile, io, sys, json, hashlib, os
import xml.etree.ElementTree as ET

src = '/opt/sweethome3d_samples/SweetHome3DExample.sh3d'
dst = '/home/ga/Documents/SweetHome3D/fire_station_starter.sh3d'
baseline_path = '/tmp/fire_station_renovation_baseline.json'

try:
    with zipfile.ZipFile(src, 'r') as zf:
        namelist = zf.namelist()

        # Identify the main XML file
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
                if ctag in ('pieceOfFurniture', 'furnitureGroup', 'doorOrWindow'):
                    to_remove.append(child)
                else:
                    strip_furniture(child)
            for child in to_remove:
                element.remove(child)

        strip_furniture(root)

        # Serialize the stripped XML
        ET.register_namespace('', '')
        modified_xml = ET.tostring(root, encoding='unicode')
        modified_xml = '<?xml version="1.0" encoding="UTF-8"?>\n' + modified_xml

        # Repackage as new ZIP, preserving non-XML resources
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as out_zf:
            for item in namelist:
                if item == xml_name:
                    out_zf.writestr(item, modified_xml.encode('utf-8'))
                else:
                    out_zf.writestr(item, zf.read(item))

    # Write the stripped .sh3d file
    with open(dst, 'wb') as f:
        f.write(buf.getvalue())

    # Compute MD5 of the starter for the anti-copy-paste gate
    with open(dst, 'rb') as f:
        starter_md5 = hashlib.md5(f.read()).hexdigest()

    # Count baseline structural elements (walls, rooms) BEFORE agent edits
    baseline_walls = 0
    baseline_rooms = 0
    for elem in root.iter():
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        if tag == 'wall':
            baseline_walls += 1
        elif tag == 'room':
            baseline_rooms += 1

    # Save baseline metrics
    baseline = {
        'furniture_count': 0,
        'furniture_names': [],
        'wall_count': baseline_walls,
        'room_count': baseline_rooms,
        'starter_md5': starter_md5,
        'starter_file': dst
    }
    with open(baseline_path, 'w') as f:
        json.dump(baseline, f, indent=2)

    print(f"Starter created: {dst} ({os.path.getsize(dst)} bytes)")
    print(f"Baseline: {baseline_walls} walls, {baseline_rooms} rooms")
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

# Copy starter to result destination so the agent is already working in the correct file
cp "$STARTER_DST" "$RESULT_DST"

# Set proper ownership
chown ga:ga "$STARTER_DST" "$RESULT_DST" 2>/dev/null || true
chown ga:ga "$BASELINE_JSON" 2>/dev/null || true

# ── Step 4: LAUNCH ────────────────────────────────────────────────────────────
echo "Launching Sweet Home 3D with fire station starter..."
setup_sweet_home_3d_task "$RESULT_DST"

echo "=== fire_station_renovation task setup complete ==="