#!/bin/bash
echo "=== Setting up survey_boundary_overlay task ==="

pkill -f librecad 2>/dev/null || true
sleep 3

if [ ! -s /home/ga/Documents/LibreCAD/floorplan.dxf ]; then
    cp /opt/librecad_samples/floorplan.dxf /home/ga/Documents/LibreCAD/floorplan.dxf 2>/dev/null || true
fi

SRC_SIZE=$(stat -c%s /home/ga/Documents/LibreCAD/floorplan.dxf 2>/dev/null || echo 0)
if [ "$SRC_SIZE" -lt 100000 ]; then
    echo "ERROR: Source floorplan.dxf is missing or too small."
    exit 1
fi

rm -f /home/ga/Documents/LibreCAD/floorplan_survey.dxf
chown -R ga:ga /home/ga/Documents/LibreCAD

python3 -c "
import ezdxf, json
try:
    doc = ezdxf.readfile('/home/ga/Documents/LibreCAD/floorplan.dxf')
    msp = doc.modelspace()
    count = len(list(msp))
    layers = [l.dxf.name for l in doc.layers]
    with open('/tmp/survey_boundary_overlay_baseline.json', 'w') as f:
        json.dump({'entity_count': count, 'layer_names': layers}, f)
    print(f'Baseline: {count} entities')
except Exception as e:
    with open('/tmp/survey_boundary_overlay_baseline.json', 'w') as f:
        json.dump({'entity_count': 967, 'layer_names': []}, f)
    print(f'Baseline fallback: {e}')
" 2>/dev/null

date +%s > /tmp/task_start_timestamp

su - ga -c "DISPLAY=:1 librecad /home/ga/Documents/LibreCAD/floorplan.dxf > /tmp/librecad_task.log 2>&1 &"
sleep 8

DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

DISPLAY=:1 import -window root /tmp/survey_boundary_overlay_start.png 2>/dev/null || true

echo "=== survey_boundary_overlay setup complete ==="
