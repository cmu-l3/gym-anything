#!/bin/bash
set -e
echo "=== Setting up Fire Alarm Markup Task ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Documents directory exists and clean up previous results
mkdir -p /home/ga/Documents/LibreCAD
rm -f /home/ga/Documents/LibreCAD/floorplan_fire_alarm.dxf
rm -f /tmp/dxf_analysis.json
rm -f /tmp/task_result.json

# 3. Ensure the floorplan.dxf exists (copy from samples if needed)
if [ ! -f "/home/ga/Documents/LibreCAD/floorplan.dxf" ]; then
    echo "Restoring floorplan.dxf from samples..."
    cp /opt/librecad_samples/floorplan.dxf /home/ga/Documents/LibreCAD/floorplan.dxf
fi
chown ga:ga /home/ga/Documents/LibreCAD/floorplan.dxf

# Record initial entity count for anti-gaming check
# We use a simple grep count of entities as a rough proxy if ezdxf isn't ready yet,
# but since ezdxf is installed in the env, we can use a python one-liner.
INITIAL_COUNT=$(python3 -c "import ezdxf; doc = ezdxf.readfile('/home/ga/Documents/LibreCAD/floorplan.dxf'); print(len(doc.modelspace()))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_entity_count.txt
echo "Initial entity count: $INITIAL_COUNT"

# 4. Generate the internal verification script
# We write this here so it's ready for export_result.sh to use inside the container.
# This avoids dependency issues on the host runner by running ezdxf inside the container.
cat > /usr/local/bin/verify_fire_alarm_dxf.py << 'EOF'
import ezdxf
import json
import sys
import os
import math

def check_dxf(file_path):
    results = {
        "valid_dxf": False,
        "layers_found": [],
        "circles_found": 0,
        "rectangles_found": 0,
        "polylines_found": 0,
        "text_found": [],
        "entity_count": 0,
        "error": None
    }

    if not os.path.exists(file_path):
        results["error"] = "File not found"
        return results

    try:
        doc = ezdxf.readfile(file_path)
        results["valid_dxf"] = True
        msp = doc.modelspace()
        results["entity_count"] = len(msp)

        # Check Layers
        for layer_name in ["FIRE-ALARM-DEVICES", "FIRE-ALARM-WIRING"]:
            if layer_name in doc.layers:
                layer = doc.layers.get(layer_name)
                results["layers_found"].append({
                    "name": layer_name,
                    "color": layer.color
                })

        # Check Entities
        # Helper to get distance
        def dist(p1, p2):
            return math.sqrt((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)

        # 1. Smoke Detectors (Circles on FIRE-ALARM-DEVICES)
        targets = [(120, 180), (360, 180), (120, 380), (360, 380)]
        circles = [e for e in msp if e.dxftype() == 'CIRCLE' and e.dxf.layer == 'FIRE-ALARM-DEVICES']
        
        found_targets = [False] * len(targets)
        for c in circles:
            center = c.dxf.center
            radius = c.dxf.radius
            # Check radius tolerance
            if abs(radius - 8) > 2:
                continue
            # Check position tolerance
            for i, t in enumerate(targets):
                if dist((center.x, center.y), t) < 10:
                    found_targets[i] = True
        results["circles_found"] = sum(found_targets)

        # 2. Control Panel (Rectangle on FIRE-ALARM-DEVICES)
        # Rectangles in DXF can be LWPOLYLINE or 4 LINEs
        # Simplified check: look for any geometry bounding box near (220, 30)
        panel_area_entities = []
        for e in msp:
            if e.dxf.layer != 'FIRE-ALARM-DEVICES': continue
            if e.dxftype() in ['LWPOLYLINE', 'POLYLINE', 'LINE']:
                # Simple bounding box check would be complex for individual lines
                # We'll rely on generic presence in that area
                try:
                    # ezdxf primitives have bbox?
                    # basic check for vertices
                    if e.dxftype() == 'LINE':
                        pts = [e.dxf.start, e.dxf.end]
                    elif e.dxftype() in ['LWPOLYLINE', 'POLYLINE']:
                        pts = e.points()
                    
                    for p in pts:
                        if 215 <= p[0] <= 265 and 25 <= p[1] <= 60:
                            panel_area_entities.append(e)
                            break
                except:
                    pass
        
        if len(panel_area_entities) >= 1:
             results["rectangles_found"] = 1

        # 3. Wiring (Polylines on FIRE-ALARM-WIRING)
        wiring = [e for e in msp if e.dxf.layer == 'FIRE-ALARM-WIRING' and e.dxftype() in ['LWPOLYLINE', 'POLYLINE']]
        results["polylines_found"] = len(wiring)

        # 4. Text Labels
        texts = [e for e in msp if e.dxftype() in ['TEXT', 'MTEXT'] and e.dxf.layer == 'FIRE-ALARM-DEVICES']
        for t in texts:
            content = t.dxf.text if t.dxftype() == 'TEXT' else t.text
            results["text_found"].append(content)

    except Exception as e:
        results["error"] = str(e)

    return results

if __name__ == "__main__":
    path = sys.argv[1]
    data = check_dxf(path)
    print(json.dumps(data))
EOF
chmod +x /usr/local/bin/verify_fire_alarm_dxf.py

# 5. Start LibreCAD
if ! pgrep -f librecad > /dev/null; then
    echo "Starting LibreCAD..."
    # Start with empty workspace, agent must open file
    su - ga -c "DISPLAY=:1 librecad &"
    sleep 5
fi

# 6. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window found."
        break
    fi
    sleep 1
done

# Maximize (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="