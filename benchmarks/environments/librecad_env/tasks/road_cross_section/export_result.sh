#!/bin/bash
set -e
echo "=== Exporting road_cross_section result ==="

# 1. Basic definitions
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/road_cross_section.dxf"
TASK_END=$(date +%s)

# 2. Check if output file exists and was modified during task
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze the DXF file using Python + ezdxf (available in this env)
# We run this analysis INSIDE the container to leverage installed libraries
# and export a JSON summary for the host verifier.

PYTHON_ANALYSIS_SCRIPT=$(cat <<EOF
import sys
import json
import re

try:
    import ezdxf
    has_ezdxf = True
except ImportError:
    has_ezdxf = False

result = {
    "valid_dxf": False,
    "layers_found": [],
    "layer_colors": {},
    "entity_counts": {},
    "text_content": [],
    "dimension_count": 0,
    "bounds": {"min_x": 0, "max_x": 0, "min_y": 0, "max_y": 0},
    "error": None
}

filepath = "$OUTPUT_PATH"

if has_ezdxf:
    try:
        doc = ezdxf.readfile(filepath)
        result["valid_dxf"] = True
        
        # Analyze Layers
        for layer in doc.layers:
            result["layers_found"].append(layer.dxf.name)
            result["layer_colors"][layer.dxf.name] = layer.dxf.color
            
        # Analyze Entities
        msp = doc.modelspace()
        
        # Bounding box initialization
        min_x, max_x, min_y, max_y = float('inf'), float('-inf'), float('inf'), float('-inf')
        has_geometry = False
        
        for e in msp:
            # Count per layer
            layer = e.dxf.layer
            result["entity_counts"][layer] = result["entity_counts"].get(layer, 0) + 1
            
            # Text content
            if e.dxftype() in ['TEXT', 'MTEXT']:
                # MText content can be complex, simple text is straight attribute
                text = ""
                if e.dxftype() == 'TEXT':
                    text = e.dxf.text
                elif e.dxftype() == 'MTEXT':
                    text = e.text  # or plain_text() method if available
                if text:
                    result["text_content"].append(text)
            
            # Dimensions
            if e.dxftype() == 'DIMENSION':
                result["dimension_count"] += 1

            # Bounding box (approximate for verification)
            # Try to get extents if possible, otherwise skip or use simplified logic
            try:
                # Basic check for lines/points to update bounds
                if e.dxftype() == 'LINE':
                    pts = [e.dxf.start, e.dxf.end]
                    for p in pts:
                        min_x = min(min_x, p.x)
                        max_x = max(max_x, p.x)
                        min_y = min(min_y, p.y)
                        max_y = max(max_y, p.y)
                    has_geometry = True
            except:
                pass

        if has_geometry:
            result["bounds"] = {
                "min_x": float(min_x), "max_x": float(max_x),
                "min_y": float(min_y), "max_y": float(max_y)
            }
            
    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "ezdxf library not found in container"

print(json.dumps(result))
EOF
)

# Run the analysis if file exists
DXF_ANALYSIS="{}"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running DXF analysis..."
    DXF_ANALYSIS=$(python3 -c "$PYTHON_ANALYSIS_SCRIPT" 2>/dev/null || echo '{"error": "Analysis script failed"}')
fi

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Check if App is still running
APP_RUNNING="false"
if pgrep -f "librecad" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "dxf_analysis": $DXF_ANALYSIS
}
EOF

# 7. Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="