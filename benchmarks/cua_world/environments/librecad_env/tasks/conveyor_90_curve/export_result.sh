#!/bin/bash
echo "=== Exporting Conveyor Curve Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/conveyor_curve.dxf"

# 1. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamp
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze DXF Geometry (Run inside container to use installed ezdxf)
# We create a temporary python script to parse the DXF and output JSON analysis
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import math
import ezdxf
from ezdxf.document import Drawing

def analyze_dxf(path):
    result = {
        "valid_dxf": False,
        "layers": {},
        "arcs": [],
        "lines": [],
        "texts": []
    }
    
    try:
        doc = ezdxf.readfile(path)
        result["valid_dxf"] = True
    except Exception as e:
        result["error"] = str(e)
        return result

    # Analyze Layers
    for layer in doc.layers:
        result["layers"][layer.dxf.name] = {
            "color": layer.dxf.color
        }

    msp = doc.modelspace()

    # Analyze Arcs (RAILS)
    for arc in msp.query('ARC'):
        result["arcs"].append({
            "layer": arc.dxf.layer,
            "center": list(arc.dxf.center),
            "radius": arc.dxf.radius,
            "start_angle": arc.dxf.start_angle,
            "end_angle": arc.dxf.end_angle
        })

    # Analyze Lines (ROLLERS, END CAPS)
    for line in msp.query('LINE'):
        start = line.dxf.start
        end = line.dxf.end
        # Calculate length
        length = math.sqrt((end[0]-start[0])**2 + (end[1]-start[1])**2)
        # Calculate angle (0-360)
        angle = math.degrees(math.atan2(end[1]-start[1], end[0]-start[0]))
        if angle < 0: angle += 360
        
        # Normalize line vector for roller check (pointing away from origin vs towards)
        # We'll just store the raw angle, verifier can handle modulo 180
        
        result["lines"].append({
            "layer": line.dxf.layer,
            "length": length,
            "angle": angle,
            "start": list(start),
            "end": list(end)
        })

    # Analyze Text
    for text in msp.query('TEXT MTEXT'):
        result["texts"].append({
            "layer": text.dxf.layer,
            "content": text.dxf.text if hasattr(text.dxf, 'text') else ""
        })

    return result

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No file path"}))
        sys.exit(1)
        
    analysis = analyze_dxf(sys.argv[1])
    print(json.dumps(analysis))
EOF

# Run the analysis script
DXF_ANALYSIS="{}"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    # We use python3 which has ezdxf installed in this env
    DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py "$OUTPUT_PATH" 2>/dev/null || echo "{\"error\": \"Analysis script failed\"}")
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size": $FILE_SIZE,
    "dxf_analysis": $DXF_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="