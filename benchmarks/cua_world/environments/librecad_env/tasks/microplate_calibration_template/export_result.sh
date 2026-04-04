#!/bin/bash
echo "=== Exporting Microplate Task Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Basic File Checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/microplate_template.dxf"

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

APP_RUNNING=$(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")

# 3. Advanced DXF Analysis (Running inside container using ezdxf)
# We create a python script to analyze the DXF geometry locally since ezdxf is in the env
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import ezdxf
import math

result = {
    "valid_dxf": False,
    "layers": {},
    "entity_counts": {},
    "wells_analysis": {
        "count": 0,
        "avg_radius": 0,
        "a1_center": None,
        "h12_center": None,
        "pitch_x_check": False,
        "pitch_y_check": False
    },
    "outline_analysis": {
        "width": 0,
        "height": 0,
        "top_left": None
    },
    "labels_found": []
}

try:
    doc = ezdxf.readfile("/home/ga/Documents/LibreCAD/microplate_template.dxf")
    result["valid_dxf"] = True
    msp = doc.modelspace()

    # Analyze Layers
    for layer in doc.layers:
        result["layers"][layer.dxf.name] = layer.dxf.color

    # Analyze Entities on WELLS layer
    wells = msp.query('CIRCLE[layer=="WELLS"]')
    result["entity_counts"]["WELLS"] = len(wells)
    
    if len(wells) > 0:
        result["wells_analysis"]["count"] = len(wells)
        radii = [c.dxf.radius for c in wells]
        result["wells_analysis"]["avg_radius"] = sum(radii) / len(radii)
        
        # Sort wells to find corners
        # Sort by Y descending (top to bottom), then X ascending (left to right)
        # Note: Y is likely negative based on task spec
        sorted_wells = sorted(wells, key=lambda e: (-e.dxf.center.y, e.dxf.center.x))
        
        # A1 should be top-left (first in sort)
        a1 = sorted_wells[0]
        result["wells_analysis"]["a1_center"] = (a1.dxf.center.x, a1.dxf.center.y)
        
        # H12 should be bottom-right (last in sort)
        h12 = sorted_wells[-1]
        result["wells_analysis"]["h12_center"] = (h12.dxf.center.x, h12.dxf.center.y)

    # Analyze Outline
    # Looking for lines or polylines on OUTLINE layer
    outline_entities = msp.query('*[layer=="OUTLINE"]')
    result["entity_counts"]["OUTLINE"] = len(outline_entities)
    
    if len(outline_entities) > 0:
        # Calculate bounding box of outline
        bbox = ezdxf.bbox.extents(outline_entities)
        width = bbox.extmax.x - bbox.extmin.x
        height = bbox.extmax.y - bbox.extmin.y
        result["outline_analysis"]["width"] = width
        result["outline_analysis"]["height"] = height
        result["outline_analysis"]["top_left"] = (bbox.extmin.x, bbox.extmax.y)

    # Analyze Labels
    text_entities = msp.query('TEXT MTEXT[layer=="LABELS"]')
    result["entity_counts"]["LABELS"] = len(text_entities)
    result["labels_found"] = [t.dxf.text for t in text_entities if hasattr(t.dxf, 'text')]

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run analysis if file exists
if [ "$OUTPUT_EXISTS" = "true" ]; then
    # ezdxf is installed in system python or pip, try running
    DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py 2>/dev/null || echo '{"error": "Analysis script failed"}')
else
    DXF_ANALYSIS='{"valid_dxf": false, "error": "File not found"}'
fi

# 4. Create Final JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "dxf_analysis": $DXF_ANALYSIS
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="