#!/bin/bash
echo "=== Exporting Nameplate Template Result ==="

OUTPUT_PATH="/home/ga/Documents/LibreCAD/nameplate_template.dxf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze the DXF file using Python + ezdxf inside the container
# We do this here because the host verifier might not have ezdxf installed,
# but the container environment is guaranteed to have it.
ANALYSIS_JSON="/tmp/dxf_analysis.json"

cat << 'EOF' > /tmp/analyze_dxf.py
import sys
import json
import os
import ezdxf

output = {
    "valid_dxf": False,
    "error": None,
    "layers": {},
    "rectangles": [],
    "circles": [],
    "texts": [],
    "entity_count": 0
}

file_path = "/home/ga/Documents/LibreCAD/nameplate_template.dxf"

if not os.path.exists(file_path):
    output["error"] = "File not found"
    print(json.dumps(output))
    sys.exit(0)

try:
    doc = ezdxf.readfile(file_path)
    msp = doc.modelspace()
    output["valid_dxf"] = True
    output["entity_count"] = len(list(msp))
    
    # Analyze Layers
    for layer in doc.layers:
        output["layers"][layer.dxf.name.upper()] = layer.dxf.color

    # Analyze Entities
    for e in msp:
        layer = e.dxf.layer.upper()
        
        # Rectangles (Lines/Polylines)
        if e.dxftype() in ['LINE', 'LWPOLYLINE', 'POLYLINE']:
            # Simplified: just storing bounding box of lines for verifier to process
            if e.dxftype() == 'LINE':
                pts = [(e.dxf.start.x, e.dxf.start.y), (e.dxf.end.x, e.dxf.end.y)]
                output["rectangles"].append({"type": "LINE", "layer": layer, "points": pts})
            elif e.dxftype() == 'LWPOLYLINE':
                pts = list(e.get_points('xy'))
                output["rectangles"].append({"type": "POLY", "layer": layer, "points": pts})
                
        # Circles
        elif e.dxftype() == 'CIRCLE':
            output["circles"].append({
                "layer": layer,
                "center": (e.dxf.center.x, e.dxf.center.y),
                "radius": e.dxf.radius
            })
            
        # Text
        elif e.dxftype() in ['TEXT', 'MTEXT']:
            content = e.dxf.text if e.dxftype() == 'TEXT' else e.text
            output["texts"].append({
                "layer": layer,
                "content": content,
                "height": e.dxf.height
            })

except Exception as e:
    output["error"] = str(e)

print(json.dumps(output))
EOF

# Run analysis script
if [ -f "$OUTPUT_PATH" ]; then
    python3 /tmp/analyze_dxf.py > "$ANALYSIS_JSON" 2>/dev/null || echo '{"error": "Analysis script failed"}' > "$ANALYSIS_JSON"
else
    echo '{"valid_dxf": false, "error": "File not found"}' > "$ANALYSIS_JSON"
fi

# 3. Check file metadata (Anti-gaming)
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Bundle everything into final result JSON
TEMP_RESULT=$(mktemp)
# Python to merge JSONs safely
python3 -c "
import json
try:
    with open('$ANALYSIS_JSON') as f:
        analysis = json.load(f)
except:
    analysis = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'file_exists': $FILE_EXISTS == True,
    'file_created_during_task': $FILE_CREATED_DURING_TASK == True,
    'file_size': int('$FILE_SIZE'),
    'dxf_analysis': analysis,
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(result))
" > "$TEMP_RESULT"

# Move to final location
cp "$TEMP_RESULT" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="