#!/bin/bash
echo "=== Exporting adjustable_motor_base results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/LibreCAD/motor_base_plate.dxf"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Metadata
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

# 3. Analyze DXF Geometry (Run python inside container to use ezdxf)
# We generate a python script to parse the DXF and output JSON stats
cat << 'EOF' > /tmp/analyze_dxf.py
import sys
import json
import ezdxf
import math

result = {
    "valid_dxf": False,
    "layers": {},
    "plate_bounds": None,
    "slot_entities": {"ARC": 0, "LINE": 0, "LWPOLYLINE": 0, "CIRCLE": 0},
    "slot_bounds": None,
    "error": None
}

file_path = "/home/ga/Documents/LibreCAD/motor_base_plate.dxf"

try:
    doc = ezdxf.readfile(file_path)
    result["valid_dxf"] = True
    msp = doc.modelspace()

    # Analyze Layers
    for layer in doc.layers:
        result["layers"][layer.dxf.name] = {
            "color": layer.dxf.color
        }

    # Analyze PLATE Layer Geometry (Expect approx 300x250 rect)
    # We calculate bounding box of all entities on PLATE layer
    plate_bbox_min = [float('inf'), float('inf')]
    plate_bbox_max = [float('-inf'), float('-inf')]
    plate_has_entities = False

    for e in msp:
        if e.dxf.layer == "PLATE":
            plate_has_entities = True
            try:
                # ezdxf bbox calculation
                if e.dxftype() == 'LINE':
                    pts = [e.dxf.start, e.dxf.end]
                elif e.dxftype() == 'LWPOLYLINE':
                    pts = list(e.points())
                else:
                    # Fallback for complex entities not strictly needed for this simple task
                    continue
                
                for p in pts:
                    plate_bbox_min[0] = min(plate_bbox_min[0], p[0])
                    plate_bbox_min[1] = min(plate_bbox_min[1], p[1])
                    plate_bbox_max[0] = max(plate_bbox_max[0], p[0])
                    plate_bbox_max[1] = max(plate_bbox_max[1], p[1])
            except:
                pass

    if plate_has_entities and plate_bbox_min[0] != float('inf'):
        result["plate_bounds"] = [plate_bbox_min[0], plate_bbox_min[1], plate_bbox_max[0], plate_bbox_max[1]]

    # Analyze SLOTS Layer Geometry
    # We count entities and check bounds
    slot_bbox_min = [float('inf'), float('inf')]
    slot_bbox_max = [float('-inf'), float('-inf')]
    slot_has_entities = False

    for e in msp:
        if e.dxf.layer == "SLOTS":
            slot_has_entities = True
            result["slot_entities"][e.dxftype()] = result["slot_entities"].get(e.dxftype(), 0) + 1
            
            # Simple bounding box update for slots
            try:
                if e.dxftype() == 'ARC':
                    # Approximate arc bounds by center +/- radius
                    c = e.dxf.center
                    r = e.dxf.radius
                    pts = [(c[0]-r, c[1]-r), (c[0]+r, c[1]+r)]
                elif e.dxftype() == 'LINE':
                    pts = [e.dxf.start, e.dxf.end]
                elif e.dxftype() == 'LWPOLYLINE':
                    pts = list(e.points())
                else:
                    continue

                for p in pts:
                    slot_bbox_min[0] = min(slot_bbox_min[0], p[0])
                    slot_bbox_min[1] = min(slot_bbox_min[1], p[1])
                    slot_bbox_max[0] = max(slot_bbox_max[0], p[0])
                    slot_bbox_max[1] = max(slot_bbox_max[1], p[1])
            except:
                pass

    if slot_has_entities and slot_bbox_min[0] != float('inf'):
        result["slot_bounds"] = [slot_bbox_min[0], slot_bbox_min[1], slot_bbox_max[0], slot_bbox_max[1]]

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run analysis if file exists
DXF_ANALYSIS="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    # ezdxf is installed in the environment
    DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py)
fi

# 4. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "dxf_analysis": $DXF_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="