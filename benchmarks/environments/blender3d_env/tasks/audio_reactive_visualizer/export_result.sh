#!/bin/bash
echo "=== Exporting Audio Visualizer Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/BlenderProjects/visualizer_completed.blend"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    OUTPUT_EXISTS="false"
    OUTPUT_MTIME="0"
fi

# ================================================================
# ANALYZE BLEND FILE WITH PYTHON
# ================================================================
# We need to check if F-Curves exist, if they are baked (high density), 
# and if they match the Z-scale channel.

ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_viz.XXXXXX.py)
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import sys

output = {
    "valid_file": False,
    "object_found": False,
    "animation_found": False,
    "target_channel_found": False,
    "keyframe_count": 0,
    "value_min": 0.0,
    "value_max": 0.0,
    "variance": 0.0
}

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/visualizer_completed.blend")
    output["valid_file"] = True
    
    obj = bpy.data.objects.get("SpeakerCone")
    if obj:
        output["object_found"] = True
        
        if obj.animation_data and obj.animation_data.action:
            output["animation_found"] = True
            action = obj.animation_data.action
            
            # Find Scale Z channel (data_path="scale", array_index=2)
            target_curve = None
            for fcurve in action.fcurves:
                if fcurve.data_path == "scale" and fcurve.array_index == 2:
                    target_curve = fcurve
                    break
            
            if target_curve:
                output["target_channel_found"] = True
                
                # Analyze keyframes
                kps = target_curve.keyframe_points
                count = len(kps)
                output["keyframe_count"] = count
                
                if count > 0:
                    values = [kp.co[1] for kp in kps]
                    v_min = min(values)
                    v_max = max(values)
                    output["value_min"] = v_min
                    output["value_max"] = v_max
                    output["variance"] = v_max - v_min

except Exception as e:
    output["error"] = str(e)

print("JSON_RESULT:" + json.dumps(output))
PYEOF

# Run analysis
if [ "$OUTPUT_EXISTS" = "true" ]; then
    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    # Extract JSON line
    JSON_DATA=$(echo "$ANALYSIS_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
else
    JSON_DATA='{"valid_file": false, "error": "File not found"}'
fi

# Clean up
rm -f "$ANALYSIS_SCRIPT"

# Combine into final result
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_mtime": $OUTPUT_MTIME,
    "task_start": $TASK_START,
    "analysis": ${JSON_DATA:-{}}
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json