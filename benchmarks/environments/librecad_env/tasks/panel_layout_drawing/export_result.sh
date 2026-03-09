#!/bin/bash
echo "=== Exporting panel_layout_drawing results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/LibreCAD/control_panel_layout.dxf"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Basic File Checks
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Advanced DXF Analysis using Python (ezdxf) inside the container
# We generate a python script to analyze the DXF content and output JSON
# This avoids needing ezdxf on the verifier host

cat << 'EOF' > /tmp/analyze_dxf.py
import sys
import json
import os

result = {
    "valid_dxf": False,
    "layers": [],
    "entity_counts": {},
    "text_content": [],
    "dimensions_count": 0,
    "bbox_area": 0
}

try:
    import ezdxf
    filename = sys.argv[1]
    
    if os.path.exists(filename):
        try:
            doc = ezdxf.readfile(filename)
            result["valid_dxf"] = True
            
            # 1. Analyze Layers
            result["layers"] = [layer.dxf.name for layer in doc.layers]
            
            # 2. Analyze Entities
            msp = doc.modelspace()
            counts = {}
            texts = []
            dims = 0
            
            # Bounding box for BACKPLATE
            x_coords = []
            y_coords = []
            
            for entity in msp:
                # Count by layer
                layer = entity.dxf.layer
                counts[layer] = counts.get(layer, 0) + 1
                
                # Collect text
                if entity.dxftype() in ['TEXT', 'MTEXT']:
                    # MTEXT content access varies slightly, simple text attribute usually works
                    content = ""
                    if hasattr(entity, 'text'):
                        content = entity.text
                    elif hasattr(entity, 'dxf') and hasattr(entity.dxf, 'text'):
                        content = entity.dxf.text
                    
                    if content:
                        texts.append(content)
                
                # Count dimensions
                if entity.dxftype() == 'DIMENSION':
                    dims += 1
                
                # Check Backplate geometry
                if layer == 'BACKPLATE' and entity.dxftype() in ['LWPOLYLINE', 'POLYLINE']:
                    # Rough bbox estimation
                    try:
                        pts = entity.get_points()
                        for p in pts:
                            x_coords.append(p[0])
                            y_coords.append(p[1])
                    except:
                        pass
            
            result["entity_counts"] = counts
            result["text_content"] = texts
            result["dimensions_count"] = dims
            
            # Calculate approx backplate area if points found
            if x_coords and y_coords:
                w = max(x_coords) - min(x_coords)
                h = max(y_coords) - min(y_coords)
                result["bbox_width"] = w
                result["bbox_height"] = h
                
        except Exception as e:
            result["error"] = str(e)
    else:
        result["error"] = "File not found"

except ImportError:
    result["error"] = "ezdxf not installed"

print(json.dumps(result))
EOF

# Run the analysis script
DXF_ANALYSIS="{}"
if [ "$FILE_EXISTS" == "true" ]; then
    DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py "$OUTPUT_FILE")
fi

# 4. Construct Final JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "dxf_analysis": $DXF_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"
rm -f /tmp/analyze_dxf.py

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="