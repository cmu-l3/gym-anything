#!/bin/bash
set -e
echo "=== Exporting tile_floor_layout results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/LibreCAD/restroom_tile_layout.dxf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence and basic stats
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Anti-gaming: Check if file was modified after task start
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

# ------------------------------------------------------------------
# Run Python script INSIDE container to analyze DXF geometry
# This avoids dependency issues on the verifier host
# ------------------------------------------------------------------
cat > /tmp/analyze_dxf.py << 'EOF'
import sys
import json
import os

result = {
    "valid_dxf": False,
    "layers_found": [],
    "walls_bbox": None,
    "border_bbox": None,
    "tiles_line_count": 0,
    "dim_count": 0,
    "text_content": [],
    "error": None
}

file_path = "/home/ga/Documents/LibreCAD/restroom_tile_layout.dxf"

try:
    if os.path.exists(file_path):
        import ezdxf
        try:
            doc = ezdxf.readfile(file_path)
            msp = doc.modelspace()
            result["valid_dxf"] = True
            
            # List layers
            result["layers_found"] = [layer.dxf.name.upper() for layer in doc.layers]
            
            def get_bbox(layer_name):
                xs, ys = [], []
                entities = [e for e in msp if e.dxf.layer.upper() == layer_name.upper()]
                for e in entities:
                    if e.dxftype() == 'LINE':
                        xs.extend([e.dxf.start.x, e.dxf.end.x])
                        ys.extend([e.dxf.start.y, e.dxf.end.y])
                    elif e.dxftype() in ('LWPOLYLINE', 'POLYLINE'):
                        for pt in e.get_points('xy'):
                            xs.append(pt[0])
                            ys.append(pt[1])
                if xs and ys:
                    return [min(xs), min(ys), max(xs), max(ys)]
                return None

            # Geometry checks
            result["walls_bbox"] = get_bbox("WALLS")
            result["border_bbox"] = get_bbox("BORDER")
            
            # Entity counts
            tiles_ents = [e for e in msp if e.dxf.layer.upper() == "TILES"]
            result["tiles_line_count"] = sum(1 for e in tiles_ents if e.dxftype() in ('LINE', 'LWPOLYLINE', 'POLYLINE'))
            
            dim_ents = [e for e in msp if "DIMENSION" in e.dxftype()]
            result["dim_count"] = len(dim_ents)
            
            # Text content
            texts = [e for e in msp if e.dxftype() in ('TEXT', 'MTEXT')]
            result["text_content"] = [e.dxf.text for e in texts if hasattr(e.dxf, 'text')]
            
        except Exception as e:
            result["error"] = f"DXF parsing error: {str(e)}"
    else:
        result["error"] = "File not found"

except ImportError:
    result["error"] = "ezdxf library not installed in container"
except Exception as e:
    result["error"] = f"Script error: {str(e)}"

print(json.dumps(result))
EOF

# Execute the analysis script
if [ "$OUTPUT_EXISTS" = "true" ]; then
    DXF_ANALYSIS=$(python3 /tmp/analyze_dxf.py)
else
    DXF_ANALYSIS='{"valid_dxf": false, "error": "File does not exist"}'
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "dxf_analysis": $DXF_ANALYSIS
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="