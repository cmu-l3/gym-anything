#!/bin/bash
echo "=== Exporting shrinkwrap_decal_application result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_BLEND="/home/ga/BlenderProjects/pipe_decal.blend"
RESULT_JSON="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check if file exists
if [ -f "$OUTPUT_BLEND" ]; then
    OUTPUT_EXISTS="true"
else
    OUTPUT_EXISTS="false"
fi

# ================================================================
# ANALYZE BLEND FILE
# ================================================================
if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Analyzing $OUTPUT_BLEND..."
    
    cat > /tmp/analyze_shrinkwrap.py << 'PYEOF'
import bpy
import json
import os

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/pipe_decal.blend")
    
    label = bpy.data.objects.get("WarningLabel")
    pipe = bpy.data.objects.get("IndustrialPipe")
    
    result = {
        "label_exists": label is not None,
        "pipe_exists": pipe is not None,
        "has_shrinkwrap": False,
        "target_correct": False,
        "offset": -1.0,
        "modifier_name": None,
        "is_active": False
    }

    if label:
        # Check modifiers
        for mod in label.modifiers:
            if mod.type == 'SHRINKWRAP':
                result["has_shrinkwrap"] = True
                result["modifier_name"] = mod.name
                result["is_active"] = mod.show_viewport
                
                if mod.target and mod.target.name == "IndustrialPipe":
                    result["target_correct"] = True
                
                result["offset"] = mod.offset
                break # Only check the first/primary shrinkwrap
    
    print("JSON_RESULT:" + json.dumps(result))

except Exception as e:
    print("JSON_RESULT:" + json.dumps({"error": str(e)}))
PYEOF

    # Run analysis
    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python /tmp/analyze_shrinkwrap.py 2>/dev/null)
    
    # Extract JSON
    JSON_DATA=$(echo "$ANALYSIS_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
    
    if [ -z "$JSON_DATA" ]; then
        JSON_DATA='{"error": "Failed to parse Blender output"}'
    fi
else
    JSON_DATA='{"output_exists": false}'
fi

# Combine with timestamp info
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$OUTPUT_BLEND" 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Write final result
cat > "$RESULT_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "analysis": $JSON_DATA
}
EOF

echo "Result saved to $RESULT_JSON"
cat "$RESULT_JSON"