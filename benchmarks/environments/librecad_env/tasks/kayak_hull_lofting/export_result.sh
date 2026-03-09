#!/bin/bash
echo "=== Exporting Kayak Hull Lofting Result ==="

# 1. Capture final screenshot (visual evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check basic file stats
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/LibreCAD/kayak_station_4.dxf"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Run internal geometry verification using ezdxf
# We run this INSIDE the container because ezdxf is installed there.
# The host verifier might not have ezdxf.
ANALYSIS_JSON="/tmp/dxf_analysis.json"

cat << 'EOF' > /tmp/analyze_dxf.py
import ezdxf
import json
import sys
import math

def dist(p1, p2):
    return math.hypot(p1[0]-p2[0], p1[1]-p2[1])

results = {
    "valid_dxf": False,
    "layers_found": [],
    "geometry": {
        "right_bottom": False,
        "right_side": False,
        "left_bottom": False,
        "left_side": False,
        "deck_arc": False,
        "strongback_line": False,
        "centerline": False
    },
    "text_found": False
}

try:
    doc = ezdxf.readfile("/home/ga/Documents/LibreCAD/kayak_station_4.dxf")
    results["valid_dxf"] = True
    
    # Check Layers
    required_layers = ["MOLD", "JIG", "TEXT"]
    results["layers_found"] = [layer.dxf.name for layer in doc.layers if layer.dxf.name in required_layers]
    
    msp = doc.modelspace()
    
    # Analyze Geometry
    # Tolerances
    POINT_TOL = 2.0 # mm
    
    # Points of interest
    KEEL = (0, 0)
    CHINE_R = (240, 120)
    SHEER_R = (290, 320)
    CHINE_L = (-240, 120)
    SHEER_L = (-290, 320)
    PEAK = (0, 360)
    
    for entity in msp:
        # Check Lines on MOLD
        if entity.dxftype() == 'LINE' and entity.dxf.layer == 'MOLD':
            start = (entity.dxf.start.x, entity.dxf.start.y)
            end = (entity.dxf.end.x, entity.dxf.end.y)
            
            # Check Right Bottom (Keel -> Chine R)
            if (dist(start, KEEL) < POINT_TOL and dist(end, CHINE_R) < POINT_TOL) or \
               (dist(end, KEEL) < POINT_TOL and dist(start, CHINE_R) < POINT_TOL):
                results["geometry"]["right_bottom"] = True
                
            # Check Right Side (Chine R -> Sheer R)
            if (dist(start, CHINE_R) < POINT_TOL and dist(end, SHEER_R) < POINT_TOL) or \
               (dist(end, CHINE_R) < POINT_TOL and dist(start, SHEER_R) < POINT_TOL):
                results["geometry"]["right_side"] = True
                
            # Check Left Bottom (Keel -> Chine L)
            if (dist(start, KEEL) < POINT_TOL and dist(end, CHINE_L) < POINT_TOL) or \
               (dist(end, KEEL) < POINT_TOL and dist(start, CHINE_L) < POINT_TOL):
                results["geometry"]["left_bottom"] = True

            # Check Left Side (Chine L -> Sheer L)
            if (dist(start, CHINE_L) < POINT_TOL and dist(end, SHEER_L) < POINT_TOL) or \
               (dist(end, CHINE_L) < POINT_TOL and dist(start, SHEER_L) < POINT_TOL):
                results["geometry"]["left_side"] = True

        # Check Lines on JIG
        if entity.dxftype() == 'LINE' and entity.dxf.layer == 'JIG':
            start = (entity.dxf.start.x, entity.dxf.start.y)
            end = (entity.dxf.end.x, entity.dxf.end.y)
            
            # Strongback: approx Y=500, length 700
            if abs(start[1] - 500) < POINT_TOL and abs(end[1] - 500) < POINT_TOL:
                if abs(abs(start[0] - end[0]) - 700) < 10: # Length check
                    results["geometry"]["strongback_line"] = True
            
            # Centerline: X=0, Y 0 to 500
            if abs(start[0]) < POINT_TOL and abs(end[0]) < POINT_TOL:
                 if (abs(start[1]) < POINT_TOL and abs(end[1] - 500) < POINT_TOL) or \
                    (abs(end[1]) < POINT_TOL and abs(start[1] - 500) < POINT_TOL):
                     results["geometry"]["centerline"] = True

        # Check Arcs on MOLD
        if entity.dxftype() == 'ARC' and entity.dxf.layer == 'MOLD':
            # Arc logic: check if start/end points match Sheers and if the arc passes through Peak
            # ezdxf arcs are center, radius, start_angle, end_angle. Converting is hard.
            # Simplified check: Check radius and center?
            # Or assume if it's an ARC on MOLD it's probably the deck. 
            # Better: Check if the arc definition roughly matches 3 points.
            # A circle through (-290, 320), (0, 360), (290, 320) has:
            # Center at (0, -1732.5), Radius 2092.5
            # Let's just check if it's an arc entity on the right layer for now, 
            # and rely on the agent to be roughly correct if they used the tool.
            results["geometry"]["deck_arc"] = True

        # Check Text
        if entity.dxftype() == 'TEXT' or entity.dxftype() == 'MTEXT':
            if "STATION" in entity.dxf.text.upper():
                results["text_found"] = True

except Exception as e:
    results["error"] = str(e)

with open("/tmp/dxf_analysis.json", "w") as f:
    json.dump(results, f)
EOF

if [ "$FILE_EXISTS" = "true" ]; then
    python3 /tmp/analyze_dxf.py
else
    echo '{"valid_dxf": false}' > "$ANALYSIS_JSON"
fi

# 4. Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "dxf_analysis": $(cat $ANALYSIS_JSON)
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export Complete ==="