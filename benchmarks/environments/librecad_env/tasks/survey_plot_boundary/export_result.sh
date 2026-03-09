#!/bin/bash
set -e
echo "=== Exporting survey_plot_boundary task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DXF_PATH="/home/ga/Documents/LibreCAD/survey_plot.dxf"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if LibreCAD was running
APP_RUNNING=$(pgrep -f librecad > /dev/null && echo "true" || echo "false")

# 3. Basic File Checks
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$DXF_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DXF_PATH")
    FILE_MTIME=$(stat -c %Y "$DXF_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Analyze DXF content using Python (running INSIDE container to use local ezdxf)
# We generate this script dynamically to ensure it runs in the container's environment
cat > /tmp/analyze_dxf_internal.py << 'EOF'
import sys
import json
import math
import os

try:
    import ezdxf
    EZDXF_AVAILABLE = True
except ImportError:
    EZDXF_AVAILABLE = False

def distance(p1, p2):
    return math.sqrt((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)

def analyze(dxf_path):
    result = {
        "valid_dxf": False,
        "layers": {},
        "polylines": [],
        "texts": [],
        "errors": []
    }

    if not os.path.exists(dxf_path):
        return result

    if not EZDXF_AVAILABLE:
        result["errors"].append("ezdxf not installed in container")
        return result

    try:
        doc = ezdxf.readfile(dxf_path)
        result["valid_dxf"] = True
    except Exception as e:
        result["errors"].append(str(e))
        return result

    # Check Layers
    for layer in doc.layers:
        result["layers"][layer.dxf.name.upper()] = {
            "color": layer.dxf.color
        }

    # Check Modelspace Entities
    msp = doc.modelspace()
    
    # Extract Polylines
    for entity in msp:
        if entity.dxftype() in ["LWPOLYLINE", "POLYLINE"]:
            poly_data = {
                "layer": entity.dxf.layer.upper(),
                "closed": entity.closed if entity.dxftype() == "LWPOLYLINE" else entity.is_closed,
                "points": []
            }
            
            # Get points
            if entity.dxftype() == "LWPOLYLINE":
                # Returns (x, y, start_width, end_width, bulge)
                points = entity.get_points(format="xy")
                poly_data["points"] = [list(p) for p in points]
            else:
                poly_data["points"] = [[v.dxf.location.x, v.dxf.location.y] for v in entity.vertices]
            
            result["polylines"].append(poly_data)

    # Extract Text
    for entity in msp:
        if entity.dxftype() in ["TEXT", "MTEXT"]:
            text_content = entity.dxf.text if entity.dxftype() == "TEXT" else entity.text
            result["texts"].append({
                "layer": entity.dxf.layer.upper(),
                "content": text_content,
                "pos": [entity.dxf.insert.x, entity.dxf.insert.y]
            })

    return result

if __name__ == "__main__":
    path = "/home/ga/Documents/LibreCAD/survey_plot.dxf"
    data = analyze(path)
    print(json.dumps(data))
EOF

# Run the analysis script
if [ "$FILE_EXISTS" = "true" ]; then
    python3 /tmp/analyze_dxf_internal.py > /tmp/dxf_analysis.json 2>/dev/null || echo "{}" > /tmp/dxf_analysis.json
else
    echo '{"valid_dxf": false, "error": "File not found"}' > /tmp/dxf_analysis.json
fi

# 5. Compile Final Result JSON
# We embed the DXF analysis into the main result file
DXF_ANALYSIS=$(cat /tmp/dxf_analysis.json)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "dxf_analysis": $DXF_ANALYSIS
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="