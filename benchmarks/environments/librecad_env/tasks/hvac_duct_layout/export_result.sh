#!/bin/bash
echo "=== Exporting HVAC Duct Layout Result ==="

OUTPUT_PATH="/home/ga/Documents/LibreCAD/hvac_duct_layout.dxf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Metadata
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze DXF Content using python (ezdxf) inside the container
# This is robust because ezdxf is installed in the environment (see scripts/install_librecad.sh)
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import ezdxf
import os

result = {
    "valid_dxf": False,
    "layers_found": [],
    "entity_counts": {},
    "text_contents": [],
    "bboxes": {},
    "error": None
}

path = "/home/ga/Documents/LibreCAD/hvac_duct_layout.dxf"

try:
    if os.path.exists(path):
        try:
            doc = ezdxf.readfile(path)
            result["valid_dxf"] = True
            
            # Check layers
            result["layers_found"] = [layer.dxf.name for layer in doc.layers]
            
            # Analyze entities
            msp = doc.modelspace()
            
            # Count entities per layer
            counts = {}
            bboxes = {}
            texts = []
            
            for entity in msp:
                layer = entity.dxf.layer
                counts[layer] = counts.get(layer, 0) + 1
                
                # Check text
                if entity.dxftype() in ['TEXT', 'MTEXT']:
                    texts.append(entity.dxf.text)
                
                # Bounding box analysis (simplified)
                # Just tracking raw coordinates of lines/polylines to see if they are in range
                if entity.dxftype() in ['LINE', 'LWPOLYLINE', 'POLYLINE']:
                    # This is a rough heuristic to avoid complex geometry processing
                    # We just need to know if stuff exists in the right regions
                    pass

            result["entity_counts"] = counts
            result["text_contents"] = texts
            
        except Exception as e:
            result["error"] = f"DXF parse error: {str(e)}"
    else:
        result["error"] = "File not found"

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run analysis
ANALYSIS_JSON="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    ANALYSIS_JSON=$(python3 /tmp/analyze_dxf.py 2>/dev/null || echo '{"error": "Analysis script failed"}')
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "dxf_analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="