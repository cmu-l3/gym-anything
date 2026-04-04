#!/bin/bash
set -e
echo "=== Exporting PCB Board Outline results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/Documents/LibreCAD/pcb_outline.dxf"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Basic File Checks
FILE_EXISTS="false"
FILE_SIZE="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 3. Advanced DXF Analysis (Running inside container where ezdxf is installed)
# We embed the python script here to run in the container environment
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import math
import os

try:
    import ezdxf
except ImportError:
    print(json.dumps({"error": "ezdxf not installed"}))
    sys.exit(0)

filepath = "/home/ga/Documents/LibreCAD/pcb_outline.dxf"
results = {
    "valid_dxf": False,
    "layers_found": {},
    "geometry_checks": []
}

if not os.path.exists(filepath):
    print(json.dumps(results))
    sys.exit(0)

try:
    doc = ezdxf.readfile(filepath)
    results["valid_dxf"] = True
    msp = doc.modelspace()
    
    # Check Layers
    target_layers = {
        "Board_Outline": 7,  # White
        "Mounting_Holes": 1, # Red
        "Keepout_Zone": 2    # Yellow
    }
    
    for layer_name, expected_color in target_layers.items():
        if layer_name in doc.layers:
            layer = doc.layers.get(layer_name)
            results["layers_found"][layer_name] = {
                "exists": True,
                "color": layer.dxf.color,
                "color_correct": layer.dxf.color == expected_color
            }
        else:
            results["layers_found"][layer_name] = {"exists": False}

    # Helper: Check for rectangle
    def find_rectangle(layer_name, x1, y1, x2, y2, tolerance=1.5):
        # Look for LWPOLYLINE
        candidates = doc.modelspace().query(f'LWPOLYLINE[layer=="{layer_name}"]')
        for e in candidates:
            pts = list(e.get_points(format="xy"))
            if len(pts) >= 4:
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                if (abs(min(xs) - x1) < tolerance and abs(max(xs) - x2) < tolerance and
                    abs(min(ys) - y1) < tolerance and abs(max(ys) - y2) < tolerance):
                    return True
        return False

    # Check Board Outline (0,0) to (100,80)
    results["geometry_checks"].append({
        "name": "board_outline_rect",
        "passed": find_rectangle("Board_Outline", 0, 0, 100, 80)
    })

    # Check Keepout Zone (10,10) to (90,70)
    results["geometry_checks"].append({
        "name": "keepout_rect",
        "passed": find_rectangle("Keepout_Zone", 10, 10, 90, 70)
    })

    # Check Mounting Holes
    holes_found = 0
    expected_holes = [(5, 5), (95, 5), (5, 75), (95, 75)]
    circles = doc.modelspace().query('CIRCLE[layer=="Mounting_Holes"]')
    
    for cx, cy in expected_holes:
        matched = False
        for c in circles:
            if (abs(c.dxf.center.x - cx) < 1.5 and 
                abs(c.dxf.center.y - cy) < 1.5 and 
                abs(c.dxf.radius - 1.6) < 0.2):
                matched = True
                break
        if matched:
            holes_found += 1
            
    results["geometry_checks"].append({
        "name": "mounting_holes_count",
        "found": holes_found,
        "expected": 4,
        "passed": holes_found >= 4
    })

except Exception as e:
    results["error"] = str(e)

print(json.dumps(results))
EOF

# Run the analysis
python3 /tmp/analyze_dxf.py > /tmp/dxf_analysis.json 2>/dev/null || echo "{}" > /tmp/dxf_analysis.json

# 4. Construct Final JSON
# Use python to safely merge the JSONs
python3 -c "
import json
import os

try:
    with open('/tmp/dxf_analysis.json') as f:
        analysis = json.load(f)
except:
    analysis = {}

result = {
    'file_exists': $FILE_EXISTS,
    'file_size': $FILE_SIZE,
    'created_during_task': $CREATED_DURING_TASK,
    'dxf_analysis': analysis,
    'task_start': $TASK_START,
    'task_end': $TASK_END
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json