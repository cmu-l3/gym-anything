#!/bin/bash
echo "=== Setting up urban_pocket_park_design task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="urban_pocket_park_design"
STARTER_DST="/home/ga/Documents/SweetHome3D/city_block_starter.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
BASELINE_JSON="/tmp/${TASK_NAME}_baseline.json"
START_TS="/tmp/${TASK_NAME}_start_ts"

# 1. Clean stale artifacts
echo "Cleaning stale artifacts..."
rm -f "$STARTER_DST"
rm -f "$RESULT_JSON"
rm -f "$BASELINE_JSON"
rm -f /home/ga/Documents/SweetHome3D/park_presentation.png
rm -f /home/ga/Documents/SweetHome3D/pocket_park_final.sh3d

# 2. Record start timestamp
date +%s > "$START_TS"
echo "Task start timestamp: $(cat $START_TS)"

# 3. Create a starter file representing an enclosed empty city lot
echo "Creating city block starter file..."
python3 << 'PYEOF'
import zipfile, io, sys, json, hashlib, os

dst = '/home/ga/Documents/SweetHome3D/city_block_starter.sh3d'
baseline_path = '/tmp/urban_pocket_park_design_baseline.json'

# Create a basic Home.xml with 4 enclosing walls forming a 20x30m lot
xml_content = """<?xml version="1.0" encoding="UTF-8"?>
<home>
  <camera x="0" y="0" z="800" fieldOfView="0.9" pitch="-0.6" yaw="0" />
  <wall xStart="-1000" yStart="-1500" xEnd="1000" yEnd="-1500" thickness="40" height="600" />
  <wall xStart="1000" yStart="-1500" xEnd="1000" yEnd="1500" thickness="40" height="600" />
  <wall xStart="1000" yStart="1500" xEnd="-1000" yEnd="1500" thickness="40" height="600" />
  <wall xStart="-1000" yStart="1500" xEnd="-1000" yEnd="-1500" thickness="40" height="600" />
</home>
"""

try:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as out_zf:
        out_zf.writestr('Home.xml', xml_content.encode('utf-8'))

    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, 'wb') as f:
        f.write(buf.getvalue())

    with open(dst, 'rb') as f:
        starter_md5 = hashlib.md5(f.read()).hexdigest()

    baseline = {
        'furniture_count': 0,
        'wall_count': 4,
        'room_count': 0,
        'dimension_count': 0,
        'starter_md5': starter_md5,
        'starter_file': dst
    }
    with open(baseline_path, 'w') as f:
        json.dump(baseline, f, indent=2)

    print(f"Starter created: {dst} ({os.path.getsize(dst)} bytes)")
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

if [ $? -ne 0 ] || [ ! -f "$STARTER_DST" ]; then
    echo "ERROR: Failed to create starter .sh3d file"
    exit 1
fi

chown -R ga:ga /home/ga/Documents/SweetHome3D
chown ga:ga "$BASELINE_JSON" 2>/dev/null || true

# 4. Launch Sweet Home 3D with the newly created starter
echo "Launching Sweet Home 3D with empty city lot starter..."
setup_sweet_home_3d_task "$STARTER_DST"

echo "=== urban_pocket_park_design task setup complete ==="