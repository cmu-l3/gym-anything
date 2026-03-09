#!/bin/bash
set -e
echo "=== Exporting Skate Ramp Profile Result ==="

OUTPUT_FILE="/home/ga/Documents/LibreCAD/quarter_pipe.dxf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if LibreCAD is still running
APP_RUNNING="false"
if pgrep -f "librecad" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Basic File Checks
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. INTERNAL GEOMETRY VERIFICATION
# We run a python script INSIDE the container to parse the DXF using ezdxf.
# This avoids dependency issues on the host verifier.
GEOMETRY_RESULT_FILE="/tmp/geometry_analysis.json"

cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import ezdxf
import math

output = {
    "valid_dxf": False,
    "layers_found": [],
    "layers_correct": False,
    "transition_arc": {"found": False, "radius": 0, "center": [0,0]},
    "coping_circle": {"found": False, "radius": 0, "center": [0,0]},
    "enclosure_lines": 0,
    "dimensions_count": 0,
    "error": None
}

filepath = "/home/ga/Documents/LibreCAD/quarter_pipe.dxf"

try:
    doc = ezdxf.readfile(filepath)
    output["valid_dxf"] = True
    msp = doc.modelspace()
    
    # 1. Check Layers
    required_layers = {"TEMPLATE": 7, "COPING": 1, "DIMENSIONS": 4}
    found_layers = {}
    for layer in doc.layers:
        found_layers[layer.dxf.name] = layer.dxf.color
    
    output["layers_found"] = list(found_layers.keys())
    
    # Check if required layers exist (ignoring color strictness for basic pass, but good to check)
    layers_ok = True
    for name in required_layers:
        if name not in found_layers:
            layers_ok = False
    output["layers_correct"] = layers_ok

    # 2. Check Geometry
    
    # Transition Arc (Radius 1800, Center 0,1800)
    # We look for ANY arc on TEMPLATE layer that matches
    for e in msp.query('ARC[layer=="TEMPLATE"]'):
        r = e.dxf.radius
        c = e.dxf.center
        # Tolerance 1.0mm
        if abs(r - 1800) < 5.0 and abs(c.x - 0) < 5.0 and abs(c.y - 1800) < 5.0:
            output["transition_arc"] = {
                "found": True, 
                "radius": r, 
                "center": [c.x, c.y]
            }
            break

    # Coping Circle (Radius 30, Center 1800,1800)
    for e in msp.query('CIRCLE[layer=="COPING"]'):
        r = e.dxf.radius
        c = e.dxf.center
        if abs(r - 30) < 2.0 and abs(c.x - 1800) < 5.0 and abs(c.y - 1800) < 5.0:
            output["coping_circle"] = {
                "found": True,
                "radius": r,
                "center": [c.x, c.y]
            }
            break
            
    # Enclosure Lines
    # Looking for horizontal deck line and vertical back line
    lines = msp.query('LINE[layer=="TEMPLATE"]')
    output["enclosure_lines"] = len(lines)
    
    # Dimensions
    dims = msp.query('DIMENSION[layer=="DIMENSIONS"]')
    output["dimensions_count"] = len(dims)

except IOError:
    output["error"] = "File not found"
except ezdxf.DXFStructureError:
    output["error"] = "Invalid DXF structure"
except Exception as e:
    output["error"] = str(e)

with open("/tmp/geometry_analysis.json", "w") as f:
    json.dump(output, f)
EOF

if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running internal DXF analysis..."
    python3 /tmp/analyze_dxf.py || echo '{"error": "Analysis script failed"}' > "$GEOMETRY_RESULT_FILE"
else
    echo '{"valid_dxf": false, "error": "No file"}' > "$GEOMETRY_RESULT_FILE"
fi

# 5. Assemble Final JSON
# We embed the geometry analysis into the main result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "geometry_analysis": $(cat "$GEOMETRY_RESULT_FILE")
}
EOF

# Clean up temp file
rm -f "$GEOMETRY_RESULT_FILE" /tmp/analyze_dxf.py

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="