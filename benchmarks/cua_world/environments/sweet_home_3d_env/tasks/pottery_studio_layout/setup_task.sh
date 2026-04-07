#!/bin/bash
echo "=== Setting up pottery_studio_layout task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="pottery_studio_layout"
STARTER_SRC="/opt/sweethome3d_samples/SweetHome3DExample.sh3d"
STARTER_DST="/home/ga/Documents/SweetHome3D/pottery_studio_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS="/tmp/${TASK_NAME}_start_ts"

# Clean previous task artifacts
rm -f "$STARTER_DST" "$RESULT_JSON" "$BASELINE_JSON"
[ -f "$STARTER_DST" ] && echo "ERROR: cleanup failed" && exit 1

# Record start time for anti-gaming checks
date +%s > "$START_TS"
echo "Task start timestamp: $(cat $START_TS)"

if [ ! -f "$STARTER_SRC" ]; then
    echo "ERROR: Source file not found: $STARTER_SRC"
    exit 1
fi

echo "Creating stripped studio starter from $STARTER_SRC ..."
python3 << 'PYEOF'
import zipfile, io, sys, json, hashlib, os
import xml.etree.ElementTree as ET

src = '/opt/sweethome3d_samples/SweetHome3DExample.sh3d'
dst = '/home/ga/Documents/SweetHome3D/pottery_studio_starter.sh3d'
baseline_path = '/tmp/pottery_studio_layout_baseline.json'

try:
    with zipfile.ZipFile(src, 'r') as zf:
        namelist = zf.namelist()
        xml_name = next((n for n in ['Home.xml', 'Home', 'home.xml', 'home'] if n in namelist), None)
        if not xml_name:
            xml_name = next((n for n in namelist if n.endswith('.xml')), None)
        if not xml_name:
            sys.exit("ERROR: no XML found in source .sh3d")

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

        # Remove all furniture from the starter file
        strip_furniture(root)

        ET.register_namespace('', '')
        modified_xml = '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding='unicode')

        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as out_zf:
            for item in namelist:
                out_zf.writestr(item, modified_xml.encode('utf-8') if item == xml_name else zf.read(item))

    with open(dst, 'wb') as f:
        f.write(buf.getvalue())

    with open(dst, 'rb') as f:
        starter_md5 = hashlib.md5(f.read()).hexdigest()

    # Count baseline structural elements so we can measure what the agent adds
    baseline = {'wall_count': 0, 'room_count': 0, 'label_count': 0, 'dimension_count': 0}
    for elem in root.iter():
        tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        if f"{tag}_count" in baseline:
            baseline[f"{tag}_count"] += 1

    baseline.update({
        'furniture_count': 0,
        'starter_md5': starter_md5,
        'starter_file': dst
    })
    
    with open(baseline_path, 'w') as f:
        json.dump(baseline, f, indent=2)

    print(f"Starter created: {dst} ({os.path.getsize(dst)} bytes)")

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

PYEXIT=$?
if [ $PYEXIT -ne 0 ] || [ ! -f "$STARTER_DST" ]; then
    echo "ERROR: Failed to create starter .sh3d file"
    exit 1
fi

chown ga:ga "$STARTER_DST" "$BASELINE_JSON" 2>/dev/null || true

# Launch Sweet Home 3D with the prepared starter file
setup_sweet_home_3d_task "$STARTER_DST"
echo "=== pottery_studio_layout task setup complete ==="