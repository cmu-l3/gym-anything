#!/bin/bash
echo "=== Exporting Grease Pencil Line Art Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/BlenderProjects/bmw_line_art.blend"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    # Check if modified/created after start
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_VALID_TIME="true"
    else
        FILE_VALID_TIME="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_VALID_TIME="false"
fi

# ================================================================
# BLENDER PYTHON ANALYSIS
# ================================================================
# We run a headless Blender instance to inspect the saved file.
# We check:
# 1. Any Grease Pencil object exists?
# 2. Does it have a Line Art modifier?
# 3. Is the target correct?
# 4. Are there baked strokes? (Anti-gaming: modifier alone isn't enough if not baked)

ANALYSIS_JSON="{}"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    cat > /tmp/analyze_gp.py << 'EOF'
import bpy
import json
import sys

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/bmw_line_art.blend")
    
    result = {
        "gp_objects_found": [],
        "has_lineart_modifier": False,
        "correct_target": False,
        "baked_strokes_count": 0,
        "modifier_details": []
    }

    # Find GP objects
    gp_objs = [o for o in bpy.data.objects if o.type == 'GPENCIL']
    
    for obj in gp_objs:
        obj_info = {"name": obj.name, "modifiers": []}
        
        # Check modifiers
        for mod in obj.grease_pencil_modifiers:
            mod_info = {"type": mod.type, "name": mod.name}
            
            if mod.type == 'GP_LINEART':
                result["has_lineart_modifier"] = True
                mod_info["source_type"] = mod.source_type
                
                # Check target
                target_name = ""
                if mod.source_type == 'COLLECTION' and mod.source_collection:
                    target_name = mod.source_collection.name
                elif mod.source_type == 'OBJECT' and mod.source_object:
                    target_name = mod.source_object.name
                
                mod_info["target"] = target_name
                
                # Loose matching for "BMW" or "Car" or "Collection"
                if "BMW" in target_name or "Car" in target_name or "Collection" in target_name:
                    result["correct_target"] = True
            
            obj_info["modifiers"].append(mod_info)

        # Check for baked strokes
        # Baked strokes exist in the data block
        stroke_count = 0
        if obj.data:
            for layer in obj.data.layers:
                for frame in layer.frames:
                    stroke_count += len(frame.strokes)
        
        obj_info["stroke_count"] = stroke_count
        result["baked_strokes_count"] += stroke_count
        
        result["gp_objects_found"].append(obj_info)

    print("JSON_START" + json.dumps(result) + "JSON_END")

except Exception as e:
    err = {"error": str(e)}
    print("JSON_START" + json.dumps(err) + "JSON_END")
EOF

    # Run analysis
    RAW_OUTPUT=$(/opt/blender/blender --background --python /tmp/analyze_gp.py 2>/dev/null)
    
    # Extract JSON
    ANALYSIS_JSON=$(echo "$RAW_OUTPUT" | grep -o "JSON_START.*JSON_END" | sed 's/JSON_START//;s/JSON_END//')
    
    if [ -z "$ANALYSIS_JSON" ]; then
        ANALYSIS_JSON='{"error": "Failed to parse Blender output"}'
    fi
fi

# ================================================================
# CREATE FINAL RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_VALID_TIME,
    "output_size_bytes": $OUTPUT_SIZE,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="