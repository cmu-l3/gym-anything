#!/bin/bash
echo "=== Exporting Drone Wing Rib result ==="

# 1. Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
date +%s > /tmp/task_end_time.txt

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/wing_rib.dxf"

# 2. Run internal verification script (using container's ezdxf)
# We do this INSIDE the container to leverage the pre-installed ezdxf library
# instead of relying on the host verifier to have it.

cat > /tmp/analyze_dxf.py << 'PYEOF'
import sys
import json
import os
import math

result = {
    "file_exists": False,
    "valid_dxf": False,
    "layers_found": [],
    "profile_valid": False,
    "profile_closed": False,
    "profile_vertex_count": 0,
    "holes_found": [],
    "error": ""
}

file_path = "/home/ga/Documents/LibreCAD/wing_rib.dxf"

if os.path.exists(file_path):
    result["file_exists"] = True
    try:
        import ezdxf
        from ezdxf.math import Vec3
        
        doc = ezdxf.readfile(file_path)
        result["valid_dxf"] = True
        
        # Check layers
        layers = [layer.dxf.name for layer in doc.layers]
        result["layers_found"] = layers
        
        msp = doc.modelspace()
        
        # Analyze PROFILE layer
        profile_entities = msp.query('OnLayer("PROFILE")')
        vertices = []
        
        for e in profile_entities:
            if e.dxftype() == 'POLYLINE' or e.dxftype() == 'LWPOLYLINE':
                if e.is_closed:
                    result["profile_closed"] = True
                # Extract vertices
                if e.dxftype() == 'LWPOLYLINE':
                    vertices.extend([p[:2] for p in e.get_points()])
                else:
                    vertices.extend([v.dxf.location[:2] for v in e.vertices])
            elif e.dxftype() == 'SPLINE':
                # Approximate spline or check control points
                # For simplicity in this task, we assume control points roughly match input
                if e.dxf.flags & 1: # Closed spline
                    result["profile_closed"] = True
                vertices.extend([p[:2] for p in e.control_points])
            elif e.dxftype() == 'LINE':
                # Treat start/end points
                vertices.append(e.dxf.start[:2])
                vertices.append(e.dxf.end[:2])
                
        result["profile_vertex_count"] = len(vertices)
        
        # Simple check: do we have enough vertices to resemble the airfoil?
        # The input had 29 points.
        if len(vertices) >= 20:
            result["profile_valid"] = True

        # Analyze CUTOUTS layer
        cutout_entities = msp.query('OnLayer("CUTOUTS")')
        for e in cutout_entities:
            if e.dxftype() == 'CIRCLE':
                # Store data for verifier.py to check
                result["holes_found"].append({
                    "center": [round(e.dxf.center.x, 2), round(e.dxf.center.y, 2)],
                    "radius": round(e.dxf.radius, 2)
                })
                
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

print(json.dumps(result))
PYEOF

# Run the analysis script using system python (where ezdxf is installed)
# If ezdxf is missing (shouldn't be), we handle it gracefully in verifier.py
if python3 -c "import ezdxf" 2>/dev/null; then
    ANALYSIS_JSON=$(python3 /tmp/analyze_dxf.py)
else
    # Fallback if ezdxf is somehow missing
    ANALYSIS_JSON='{"file_exists": '$( [ -f "$OUTPUT_PATH" ] && echo "true" || echo "false" )', "valid_dxf": false, "error": "ezdxf not installed in env"}'
fi

# 3. Check timestamps for anti-gaming
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
else
    FILE_SIZE="0"
fi

# 4. Construct final JSON result
# We embed the Python analysis result into the main result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "dxf_analysis": $ANALYSIS_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="