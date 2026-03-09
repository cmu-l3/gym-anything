#!/bin/bash
echo "=== Exporting apply_hatch_pattern result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_ENTITY_COUNT=$(cat /tmp/initial_entity_count.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/LibreCAD/floorplan_hatched.dxf"
ORIGINAL_PATH="/home/ga/Documents/LibreCAD/floorplan.dxf"

# Check if application was running
APP_RUNNING=$(pgrep -f "librecad" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# -----------------------------------------------------------------------------
# Analyze the DXF file using Python + ezdxf (installed in environment)
# We do this INSIDE the container to utilize the environment's tools
# and export a rich JSON summary for the host verifier.
# -----------------------------------------------------------------------------
ANALYSIS_JSON="/tmp/dxf_analysis.json"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    
    # Check file modification time against task start
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi

    # Run Python analysis script
    cat << 'EOF' > /tmp/analyze_dxf.py
import sys
import json
import os
import ezdxf

result = {
    "valid_dxf": False,
    "layers": {},
    "entity_count": 0,
    "hatch_patterns": [],
    "hatch_layers": [],
    "concrete_pad_entities": [],
    "bbox_check": {"width": 0, "height": 0, "center_x": 0, "center_y": 0}
}

try:
    doc = ezdxf.readfile(sys.argv[1])
    result["valid_dxf"] = True
    msp = doc.modelspace()
    result["entity_count"] = len(list(msp))
    
    # Analyze Layers
    for layer in doc.layers:
        result["layers"][layer.dxf.name] = {
            "color": layer.dxf.color
        }
    
    # Analyze Hatches
    hatches = msp.query("HATCH")
    for hatch in hatches:
        result["hatch_patterns"].append(hatch.dxf.pattern_name)
        result["hatch_layers"].append(hatch.dxf.layer)
        
    # Analyze Entities on CONCRETE_PAD
    pad_entities = msp.query('*[layer=="CONCRETE_PAD"]')
    for e in pad_entities:
        etype = e.dxftype()
        info = {"type": etype}
        
        # Calculate bounding box for rectangle validation
        if etype in ["LWPOLYLINE", "POLYLINE"]:
            try:
                # Simple bbox approximation for polyline
                pts = list(e.vertices())
                if len(pts) > 0:
                    xs = [p[0] for p in pts]
                    ys = [p[1] for p in pts]
                    w = max(xs) - min(xs)
                    h = max(ys) - min(ys)
                    result["concrete_pad_entities"].append({
                        "type": etype, 
                        "width": w, 
                        "height": h,
                        "closed": e.closed
                    })
            except:
                pass
        elif etype == "HATCH":
             # HATCH entities don't always have easy bbox, skip for now
             result["concrete_pad_entities"].append({"type": etype})
        else:
             result["concrete_pad_entities"].append({"type": etype})

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF
    
    # Run the analysis
    python3 /tmp/analyze_dxf.py "$OUTPUT_PATH" > "$ANALYSIS_JSON" 2>/dev/null || echo '{"valid_dxf": false, "error": "Analysis crashed"}' > "$ANALYSIS_JSON"
    
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    echo '{"valid_dxf": false, "error": "File not found"}' > "$ANALYSIS_JSON"
fi

# -----------------------------------------------------------------------------
# Create Final Result JSON
# -----------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
ANALYSIS_CONTENT=$(cat "$ANALYSIS_JSON")

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_entity_count": $INITIAL_ENTITY_COUNT,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "dxf_analysis": $ANALYSIS_CONTENT
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON" "$ANALYSIS_JSON" /tmp/analyze_dxf.py

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="