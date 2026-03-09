#!/bin/bash
set -e
echo "=== Exporting Drawing Template Results ==="

# Define paths
OUTPUT_FILE="/home/ga/Documents/LibreCAD/a3_template.dxf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python script to analyze DXF content inside the container
# We use the container's python environment which has ezdxf installed
cat << 'EOF' > /tmp/analyze_dxf.py
import sys
import json
import os
import time

result = {
    "file_exists": False,
    "file_size": 0,
    "is_valid_dxf": False,
    "layers": [],
    "lines": [],
    "polylines": [],
    "texts": [],
    "file_mtime": 0
}

filepath = sys.argv[1]

if os.path.exists(filepath):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(filepath)
    result["file_mtime"] = os.path.getmtime(filepath)
    
    try:
        import ezdxf
        doc = ezdxf.readfile(filepath)
        result["is_valid_dxf"] = True
        
        # Extract Layers
        result["layers"] = [layer.dxf.name for layer in doc.layers]
        
        # Extract Modelspace Entities
        msp = doc.modelspace()
        
        # Lines
        for line in msp.query('LINE'):
            result["lines"].append({
                "layer": line.dxf.layer,
                "start": list(line.dxf.start)[:2], # x, y only
                "end": list(line.dxf.end)[:2]
            })
            
        # Polylines (LWPOLYLINE) - often used for rectangles
        for poly in msp.query('LWPOLYLINE'):
            points = []
            if poly.is_closed:
                # Get points
                with poly.points() as pts:
                    points = [list(p)[:2] for p in pts]
            result["polylines"].append({
                "layer": poly.dxf.layer,
                "points": points,
                "is_closed": poly.is_closed
            })
            
        # Text and MText
        for text in msp.query('TEXT MTEXT'):
            # Handling both TEXT and MTEXT content access
            content = text.dxf.text if text.dxftype() == 'TEXT' else text.text
            # Position is insert point
            pos = list(text.dxf.insert)[:2]
            result["texts"].append({
                "layer": text.dxf.layer,
                "content": content,
                "pos": pos
            })
            
    except Exception as e:
        result["error"] = str(e)
        # If ezdxf fails, we still return the file existence info

print(json.dumps(result))
EOF

# 3. Run analysis
echo "Analyzing DXF file..."
ANALYSIS="{}"
if [ -f "$OUTPUT_FILE" ]; then
    ANALYSIS=$(python3 /tmp/analyze_dxf.py "$OUTPUT_FILE")
fi

# 4. Check if LibreCAD is running
APP_RUNNING=$(pgrep -f librecad > /dev/null && echo "true" || echo "false")

# 5. Create Final JSON Result
cat > "$RESULT_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $(date +%s),
    "app_was_running": $APP_RUNNING,
    "dxf_analysis": $ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Set permissions for host access
chmod 666 "$RESULT_JSON"
chmod 666 /tmp/task_final.png 2>/dev/null || true

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="