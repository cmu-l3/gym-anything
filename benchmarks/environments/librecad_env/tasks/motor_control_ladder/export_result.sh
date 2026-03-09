#!/bin/bash
echo "=== Exporting motor_control_ladder results ==="

OUTPUT_PATH="/home/ga/Documents/LibreCAD/motor_control_ladder.dxf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# check if app is running
APP_RUNNING=$(pgrep -f librecad > /dev/null && echo "true" || echo "false")

# ==============================================================================
# Python Script: Analyze DXF inside container
# We run this HERE because ezdxf is installed in the container environment,
# but might not be available on the host verifier.
# ==============================================================================
cat << 'EOF' > /tmp/analyze_dxf.py
import sys
import json
import os
import time

output_path = "/home/ga/Documents/LibreCAD/motor_control_ladder.dxf"
result = {
    "exists": False,
    "valid_dxf": False,
    "file_size": 0,
    "layers": {},
    "entity_counts": {},
    "text_content": [],
    "spatial_check": {"vertical_lines": 0, "horizontal_lines": 0}
}

try:
    if os.path.exists(output_path):
        result["exists"] = True
        result["file_size"] = os.path.getsize(output_path)
        
        # Only try to parse if file has content
        if result["file_size"] > 0:
            import ezdxf
            try:
                doc = ezdxf.readfile(output_path)
                result["valid_dxf"] = True
                
                # Analyze Layers
                for layer in doc.layers:
                    result["layers"][layer.dxf.name] = layer.dxf.color
                
                # Analyze Entities
                msp = doc.modelspace()
                for e in msp:
                    # Count entity types
                    etype = e.dxftype()
                    result["entity_counts"][etype] = result["entity_counts"].get(etype, 0) + 1
                    
                    # Extract text
                    if etype in ['TEXT', 'MTEXT']:
                        result["text_content"].append(e.dxf.text)
                    
                    # Simple spatial check for rails/rungs
                    if etype == 'LINE':
                        start = e.dxf.start
                        end = e.dxf.end
                        dx = abs(start.x - end.x)
                        dy = abs(start.y - end.y)
                        if dy > dx and dy > 100: # Vertical-ish long line
                            result["spatial_check"]["vertical_lines"] += 1
                        if dx > dy and dx > 100: # Horizontal-ish long line
                            result["spatial_check"]["horizontal_lines"] += 1

            except Exception as e:
                result["error"] = f"DXF Parse Error: {str(e)}"
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Execute analysis script
ANALYSIS_JSON="{}"
if [ -f "$OUTPUT_PATH" ]; then
    ANALYSIS_JSON=$(python3 /tmp/analyze_dxf.py)
fi

# Check file timestamps
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_PATH" ]; then
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "dxf_analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
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