#!/bin/bash
echo "=== Exporting Grain Facility Task Results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/grain_facility.dxf"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamps
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Run Internal DXF Analysis (using container's ezdxf)
# We generate a python script to parse the DXF and extract geometry/layers
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import math

try:
    import ezdxf
except ImportError:
    print(json.dumps({"error": "ezdxf not installed"}))
    sys.exit(0)

def dist(p1, p2):
    return math.hypot(p1[0] - p2[0], p1[1] - p2[1])

results = {
    "parse_error": False,
    "layer_count": 0,
    "layers_found": [],
    "bins_found": 0,
    "bins_correct_pos": 0,
    "pit_found": False,
    "road_found": False,
    "conveyors_found": 0,
    "text_labels_found": 0,
    "dimensions_found": 0,
    "entities_on_correct_layers": True
}

dxf_path = "/home/ga/Documents/LibreCAD/grain_facility.dxf"

try:
    doc = ezdxf.readfile(dxf_path)
    msp = doc.modelspace()
    
    # Check Layers
    required_layers = ["BINS", "STRUCTURES", "ROADS", "CONVEYOR", "TEXT", "DIMENSIONS"]
    existing_layers = [layer.dxf.name for layer in doc.layers]
    results["layers_found"] = [l for l in required_layers if any(e.upper() == l for e in existing_layers)]
    results["layer_count"] = len(results["layers_found"])

    # Check Bins (Circles on BINS layer)
    # Target centers: (0,0), (60,0), (0,60), (60,60). Radius 10.
    targets = [(0,0), (60,0), (0,60), (60,60)]
    bin_circles = msp.query('CIRCLE[layer=="BINS"]')
    
    valid_bins = []
    for circle in bin_circles:
        if abs(circle.dxf.radius - 10) < 2.0: # Radius tolerance
            valid_bins.append(circle.dxf.center)
            
    results["bins_found"] = len(valid_bins)
    
    # Check positions
    matched_targets = 0
    for t in targets:
        for b in valid_bins:
            if dist((b.x, b.y), t) < 5.0:
                matched_targets += 1
                break
    results["bins_correct_pos"] = matched_targets

    # Check Dump Pit (Rect on STRUCTURES)
    # Expected approx center (30,30) width 10
    structures = msp.query('LWPOLYLINE[layer=="STRUCTURES"] LINE[layer=="STRUCTURES"] POLYLINE[layer=="STRUCTURES"]')
    # Simplification: check if there is bounding box covering roughly 25,25 to 35,35
    has_pit = False
    if len(structures) > 0:
        # Heuristic: Check if entities exist near 30,30
        for e in structures:
            # Checking bounding box is complex with diverse entity types, 
            # simplest is to verify "something" exists on the layer in the right area
            # But let's be lenient: if layer has geometry, we count it, VLM verifies shape
            has_pit = True
    results["pit_found"] = has_pit

    # Check Road (Layer ROADS)
    roads = msp.query('*[layer=="ROADS"]')
    results["road_found"] = len(roads) > 0

    # Check Conveyors (Lines on CONVEYOR)
    conveyors = msp.query('LINE[layer=="CONVEYOR"]')
    # Expect lines connecting bins to (30,30)
    valid_conveyors = 0
    center = (30,30)
    for line in conveyors:
        d1 = dist((line.dxf.start.x, line.dxf.start.y), center)
        d2 = dist((line.dxf.end.x, line.dxf.end.y), center)
        # One end should be near center (30,30), other end near a bin
        if d1 < 5.0 or d2 < 5.0:
            valid_conveyors += 1
    results["conveyors_found"] = valid_conveyors

    # Check Text
    texts = msp.query('TEXT MTEXT')
    label_count = 0
    for t in texts:
        content = t.dxf.text if t.dxftype() == 'TEXT' else t.text
        content = content.upper()
        if "BIN" in content or "DUMP" in content or "PIT" in content:
            label_count += 1
    results["text_labels_found"] = label_count

    # Check Dimensions
    dims = msp.query('DIMENSION')
    results["dimensions_found"] = len(dims)

except Exception as e:
    results["parse_error"] = str(e)

print(json.dumps(results))
EOF

# Execute analysis if file exists
if [ "$FILE_EXISTS" = "true" ]; then
    python3 /tmp/analyze_dxf.py > /tmp/dxf_analysis.json 2>/dev/null || echo '{"error": "Analysis script failed"}' > /tmp/dxf_analysis.json
else
    echo '{}' > /tmp/dxf_analysis.json
fi

# 4. Construct Final JSON
# We embed the DXF analysis into the main result file
ANALYSIS_CONTENT=$(cat /tmp/dxf_analysis.json)
APP_RUNNING=$(pgrep -f librecad > /dev/null && echo "true" || echo "false")

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "dxf_analysis": $ANALYSIS_CONTENT
}
EOF

# Make result accessible
chmod 666 /tmp/task_result.json

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="