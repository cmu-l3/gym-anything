#!/bin/bash
echo "=== Exporting shaft_keyway_section results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/LibreCAD/shaft_keyway_section.dxf"

# 1. Check file existence and modification time
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
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

# 2. Analyze DXF content using Python (since ezdxf is installed in env)
# We generate a temporary python script to perform geometric analysis inside the container
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import ezdxf
import math

result = {
    "valid_dxf": False,
    "has_correct_circle": False,
    "circle_radius": 0,
    "layers_found": [],
    "hatch_count": 0,
    "dimension_count": 0,
    "text_content": [],
    "entity_count": 0
}

try:
    doc = ezdxf.readfile("/home/ga/Documents/LibreCAD/shaft_keyway_section.dxf")
    result["valid_dxf"] = True
    msp = doc.modelspace()
    
    # Check Layers
    result["layers_found"] = [layer.dxf.name.upper() for layer in doc.layers]
    
    # Check Entities
    entities = list(msp)
    result["entity_count"] = len(entities)
    
    # Check Circle (Shaft)
    circles = [e for e in entities if e.dxftype() == 'CIRCLE']
    for c in circles:
        # Looking for ~25mm radius (50mm diameter)
        if 24.0 <= c.dxf.radius <= 26.0:
            result["has_correct_circle"] = True
            result["circle_radius"] = c.dxf.radius
            break
            
    # Check Hatching
    result["hatch_count"] = sum(1 for e in entities if e.dxftype() == 'HATCH')
    
    # Check Dimensions
    dims = [e for e in entities if e.dxftype() == 'DIMENSION']
    result["dimension_count"] = len(dims)
    
    # Check Text content (MTEXT and TEXT)
    texts = [e for e in entities if e.dxftype() in ('TEXT', 'MTEXT')]
    text_content = []
    for t in texts:
        # MTEXT has 'text' attribute, TEXT has 'text' attribute
        # Some older ezdxf versions or specific entity types might differ, but .dxf.text is standard for TEXT
        content = ""
        if t.dxftype() == 'TEXT':
            content = t.dxf.text
        elif t.dxftype() == 'MTEXT':
            content = t.text  # MTEXT content access
        if content:
            text_content.append(content)
    
    # Also check if dimension text overrides exist
    for d in dims:
        if hasattr(d.dxf, 'text') and d.dxf.text:
            text_content.append(d.dxf.text)
            
    result["text_content"] = text_content

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Run analysis if file exists
if [ "$OUTPUT_EXISTS" = "true" ]; then
    DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py 2>/dev/null || echo '{"valid_dxf": false, "error": "Analysis script failed"}')
else
    DXF_ANALYSIS='{"valid_dxf": false, "reason": "File not found"}'
fi

# 3. Check if LibreCAD is still running
APP_RUNNING=$(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "dxf_analysis": $DXF_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="