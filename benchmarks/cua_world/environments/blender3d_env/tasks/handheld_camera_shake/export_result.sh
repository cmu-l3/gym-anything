#!/bin/bash
echo "=== Exporting handheld_camera_shake result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

OUTPUT_BLEND="/home/ga/BlenderProjects/handheld_cam.blend"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check file status
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_BLEND" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_BLEND")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_BLEND")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Analyze the blend file using Blender Python
echo "Analyzing animation data..."
ANALYSIS_JSON="{}"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_shake.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json

try:
    # Open the file
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/handheld_cam.blend")
    
    result = {
        "camera_found": False,
        "action_found": False,
        "modifiers": []
    }
    
    # Find camera
    cam = bpy.data.objects.get("Camera")
    if not cam:
        # Try active object or scene camera
        cam = bpy.context.scene.camera
        
    if cam:
        result["camera_found"] = True
        if cam.animation_data and cam.animation_data.action:
            result["action_found"] = True
            action = cam.animation_data.action
            
            # Inspect F-Curves
            for fcurve in action.fcurves:
                # We care about rotation_euler
                if fcurve.data_path == "rotation_euler":
                    axis_index = fcurve.array_index # 0=X, 1=Y, 2=Z
                    axis_name = ['X', 'Y', 'Z'][axis_index] if axis_index < 3 else 'Unknown'
                    
                    for mod in fcurve.modifiers:
                        mod_info = {
                            "axis": axis_name,
                            "type": mod.type,
                            "active": mod.active,
                            "show_expanded": mod.show_expanded
                        }
                        
                        if mod.type == 'NOISE':
                            mod_info["scale"] = mod.scale
                            mod_info["strength"] = mod.strength
                            mod_info["phase"] = mod.phase
                            mod_info["depth"] = mod.depth
                            
                        result["modifiers"].append(mod_info)

    print("JSON_RESULT:" + json.dumps(result))

except Exception as e:
    print(f"Error: {e}")
    print("JSON_RESULT:" + json.dumps({"error": str(e)}))
PYEOF

    # Run analysis
    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    EXTRACTED_JSON=$(echo "$ANALYSIS_OUTPUT" | grep "^JSON_RESULT:" | sed 's/^JSON_RESULT://')
    
    if [ -n "$EXTRACTED_JSON" ]; then
        ANALYSIS_JSON="$EXTRACTED_JSON"
    fi
    rm -f "$ANALYSIS_SCRIPT"
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "output_size": $OUTPUT_SIZE,
    "analysis": $ANALYSIS_JSON
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json