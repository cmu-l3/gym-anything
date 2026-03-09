#!/bin/bash
echo "=== Setting up as_built_markup task ==="

# Kill any running LibreCAD instance
pkill -f librecad 2>/dev/null || true
sleep 3

# Ensure the real floor plan source is available
if [ ! -s /home/ga/Documents/LibreCAD/floorplan.dxf ]; then
    cp /opt/librecad_samples/floorplan.dxf /home/ga/Documents/LibreCAD/floorplan.dxf 2>/dev/null || true
fi

# Validate source file exists and is real (must be > 100KB)
SRC_SIZE=$(stat -c%s /home/ga/Documents/LibreCAD/floorplan.dxf 2>/dev/null || echo 0)
if [ "$SRC_SIZE" -lt 100000 ]; then
    echo "ERROR: Source floorplan.dxf is missing or too small (${SRC_SIZE} bytes)."
    exit 1
fi
echo "Source file confirmed: ${SRC_SIZE} bytes"

# Remove any previous output to ensure clean state
rm -f /home/ga/Documents/LibreCAD/floorplan_asbuilt.dxf

chown -R ga:ga /home/ga/Documents/LibreCAD

# Record baseline entity count for anti-gaming verification
python3 -c "
import ezdxf, json, sys
try:
    doc = ezdxf.readfile('/home/ga/Documents/LibreCAD/floorplan.dxf')
    msp = doc.modelspace()
    count = len(list(msp))
    layers = [l.dxf.name for l in doc.layers]
    with open('/tmp/as_built_markup_baseline.json', 'w') as f:
        json.dump({'entity_count': count, 'layer_names': layers}, f)
    print(f'Baseline: {count} entities, {len(layers)} layers')
except Exception as e:
    # fallback baseline
    with open('/tmp/as_built_markup_baseline.json', 'w') as f:
        json.dump({'entity_count': 967, 'layer_names': []}, f)
    print(f'Baseline fallback (967): {e}')
" 2>/dev/null

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp recorded: $(cat /tmp/task_start_timestamp)"

# Open LibreCAD with the source floor plan
su - ga -c "DISPLAY=:1 librecad /home/ga/Documents/LibreCAD/floorplan.dxf > /tmp/librecad_task.log 2>&1 &"
sleep 8

# Maximize the window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/as_built_markup_start.png 2>/dev/null || true

echo "=== as_built_markup setup complete ==="
