#!/bin/bash
echo "=== Exporting Water Well Section results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Documents/LibreCAD/water_well_section.dxf"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check basic file attributes
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze DXF content using Python (running inside container where ezdxf is installed)
# We create a temporary script to parse the DXF and output JSON analysis
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import ezdxf
from ezdxf.lldxf.const import DXFStructureError

def analyze_dxf(file_path):
    result = {
        "valid_dxf": False,
        "layers": [],
        "entity_counts": {},
        "text_content": [],
        "bounds": {"min_y": 0, "max_y": 0},
        "error": None
    }
    
    try:
        doc = ezdxf.readfile(file_path)
        result["valid_dxf"] = True
        
        # Analyze Layers
        result["layers"] = [layer.dxf.name for layer in doc.layers]
        
        # Analyze Entities
        msp = doc.modelspace()
        entity_counts = {}
        text_content = []
        min_y = float('inf')
        max_y = float('-inf')
        
        for entity in msp:
            # Count entities per layer
            layer = entity.dxf.layer
            if layer not in entity_counts:
                entity_counts[layer] = 0
            entity_counts[layer] += 1
            
            # Extract Text
            if entity.dxftype() in ['TEXT', 'MTEXT']:
                text_content.append(entity.dxf.text)
                
            # Check Bounds (approximate via control points)
            try:
                # Basic check for lines/points
                if entity.dxftype() == 'LINE':
                    ys = [entity.dxf.start[1], entity.dxf.end[1]]
                    min_y = min(min_y, min(ys))
                    max_y = max(max_y, max(ys))
                elif entity.dxftype() in ['TEXT', 'INSERT', 'CIRCLE']:
                    y = entity.dxf.insert[1]
                    min_y = min(min_y, y)
                    max_y = max(max_y, y)
            except Exception:
                pass
                
        result["entity_counts"] = entity_counts
        result["text_content"] = text_content
        if min_y != float('inf'):
            result["bounds"] = {"min_y": min_y, "max_y": max_y}
            
    except Exception as e:
        result["error"] = str(e)
        
    return result

if __name__ == "__main__":
    path = sys.argv[1]
    analysis = analyze_dxf(path)
    print(json.dumps(analysis))
EOF

# Run the analysis if file exists
DXF_ANALYSIS="{}"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running DXF analysis..."
    DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py "$OUTPUT_PATH")
fi

# 4. Check if LibreCAD was running
APP_RUNNING=$(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")

# 5. Compile full result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "dxf_analysis": $DXF_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"
rm -f /tmp/analyze_dxf.py

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="