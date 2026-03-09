#!/bin/bash
echo "=== Exporting parking_lot_striping result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/LibreCAD/parking_lot.dxf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if file exists
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
fi

# Run internal DXF analysis using the container's ezdxf installation
# We do this here because the host runner might not have ezdxf installed.
# The script outputs a JSON object with the analysis.

cat > /tmp/analyze_dxf.py << 'PYEOF'
import ezdxf
import json
import sys
import os

filepath = "/home/ga/Documents/LibreCAD/parking_lot.dxf"
result = {
    "valid_dxf": False,
    "layers_found": {},
    "entity_counts": {},
    "text_content": [],
    "boundary_bbox": None,
    "striping_x_coords": []
}

if os.path.exists(filepath):
    try:
        doc = ezdxf.readfile(filepath)
        result["valid_dxf"] = True
        
        # Analyze Layers
        for layer in doc.layers:
            result["layers_found"][layer.dxf.name] = layer.dxf.color
            
        # Analyze Entities
        msp = doc.modelspace()
        
        # Count entities per layer
        counts = {}
        for e in msp:
            layer = e.dxf.layer
            counts[layer] = counts.get(layer, 0) + 1
            
            # Collect text
            if e.dxftype() in ['TEXT', 'MTEXT']:
                if hasattr(e.dxf, 'text'):
                    result["text_content"].append(e.dxf.text)
                elif hasattr(e, 'text'): # MText
                    result["text_content"].append(e.text)
            
            # Analyze Boundary geometry (approximate)
            if layer == "LOT-BOUNDARY" and e.dxftype() in ['LINE', 'LWPOLYLINE']:
                # This is a basic heuristic check, not a full geometric solver
                pass

            # Analyze Striping vertical lines
            if layer == "STRIPING" and e.dxftype() == 'LINE':
                # Check for vertical lines (start.x approx equal to end.x)
                if abs(e.dxf.start.x - e.dxf.end.x) < 0.1:
                    result["striping_x_coords"].append(round(e.dxf.start.x, 1))

        result["entity_counts"] = counts
        
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Execute the analysis script
DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py 2>/dev/null || echo '{"valid_dxf": false, "error": "Analysis script failed"}')

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "dxf_analysis": $DXF_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permission fix
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="