#!/bin/bash
echo "=== Exporting Irrigation Pivot Layout Result ==="

# Paths
OUTPUT_PATH="/home/ga/Documents/LibreCAD/irrigation_layout.dxf"
TASK_START_FILE="/tmp/task_start_time.txt"
ANALYSIS_JSON="/tmp/dxf_analysis.json"
FINAL_JSON="/tmp/task_result.json"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Basic file checks
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Run Python DXF Analysis (inside container where ezdxf is installed)
# We embed the python script here to run within the environment
cat << 'EOF' > /tmp/analyze_dxf_internal.py
import sys
import json
import math
import os

try:
    import ezdxf
except ImportError:
    print(json.dumps({"error": "ezdxf not installed"}))
    sys.exit(0)

def analyze(filepath):
    if not os.path.exists(filepath):
        return {"error": "File not found"}
        
    try:
        doc = ezdxf.readfile(filepath)
    except Exception as e:
        return {"error": f"Invalid DXF: {str(e)}"}

    msp = doc.modelspace()
    
    # Analyze Layers
    layers = [layer.dxf.name for layer in doc.layers]
    
    # Analyze Entities
    entities = []
    circles = []
    lines = []
    texts = []
    
    for e in msp:
        etype = e.dxftype()
        base_info = {"type": etype, "layer": e.dxf.layer}
        
        if etype == "CIRCLE":
            base_info["center"] = [round(e.dxf.center.x, 2), round(e.dxf.center.y, 2)]
            base_info["radius"] = round(e.dxf.radius, 2)
            circles.append(base_info)
            
        elif etype == "LINE":
            base_info["start"] = [round(e.dxf.start.x, 2), round(e.dxf.start.y, 2)]
            base_info["end"] = [round(e.dxf.end.x, 2), round(e.dxf.end.y, 2)]
            lines.append(base_info)
            
        elif etype in ["TEXT", "MTEXT"]:
            # Handle both TEXT and MTEXT text content access
            content = e.text if etype == "MTEXT" else e.dxf.text
            base_info["text"] = content
            texts.append(base_info)
            
        entities.append(base_info)

    return {
        "valid_dxf": True,
        "layers": layers,
        "entity_counts": {
            "circle": len(circles),
            "line": len(lines),
            "text": len(texts),
            "total": len(entities)
        },
        "data": {
            "circles": circles,
            "lines": lines,
            "texts": texts
        }
    }

if __name__ == "__main__":
    filepath = "/home/ga/Documents/LibreCAD/irrigation_layout.dxf"
    result = analyze(filepath)
    print(json.dumps(result))
EOF

# Run the analysis
python3 /tmp/analyze_dxf_internal.py > "$ANALYSIS_JSON" 2>/dev/null || echo '{"error": "Analysis script failed"}' > "$ANALYSIS_JSON"

# 4. Check if LibreCAD is running
APP_RUNNING="false"
if pgrep -f "librecad" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Combine into final JSON
# We use python to merge the bash variables and the analysis json safely
python3 -c "
import json
import sys

try:
    with open('$ANALYSIS_JSON', 'r') as f:
        analysis = json.load(f)
except:
    analysis = {}

result = {
    'task_meta': {
        'task_start': $TASK_START,
        'app_running': $APP_RUNNING, 
        'file_exists': $FILE_EXISTS,
        'file_created_during_task': $FILE_CREATED_DURING_TASK,
        'file_size': $FILE_SIZE
    },
    'dxf_analysis': analysis
}

with open('$FINAL_JSON', 'w') as f:
    json.dump(result, f)
"

# 6. Cleanup permission for the host to read
chmod 644 "$FINAL_JSON" /tmp/task_final.png 2>/dev/null || true

echo "Result saved to $FINAL_JSON"
cat "$FINAL_JSON"
echo "=== Export complete ==="