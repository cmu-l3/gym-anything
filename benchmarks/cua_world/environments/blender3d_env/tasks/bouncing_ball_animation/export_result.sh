#!/bin/bash
echo "=== Exporting bouncing_ball_animation result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_BLEND="/home/ga/BlenderProjects/bouncing_ball.blend"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_EXISTS="false"
IS_VALID_BLEND="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_BLEND" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_BLEND" 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check magic bytes
    MAGIC=$(head -c 7 "$OUTPUT_BLEND" 2>/dev/null | tr -d '\0')
    if [ "$MAGIC" = "BLENDER" ]; then
        IS_VALID_BLEND="true"
    fi
fi

# ================================================================
# ANALYZE BLEND FILE (HEADLESS)
# ================================================================
# This script inspects the saved file for:
# 1. Sphere object
# 2. Animation keyframes on Z axis
# 3. Trajectory analysis (bounces, horizontal travel)

SCENE_ANALYSIS='{"error": "File not found or invalid"}'

if [ "$IS_VALID_BLEND" = "true" ]; then
    echo "Analyzing animation data in $OUTPUT_BLEND..."
    
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_anim.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import math

filepath = "/home/ga/BlenderProjects/bouncing_ball.blend"
bpy.ops.wm.open_mainfile(filepath=filepath)

scene = bpy.context.scene
result = {
    "frame_start": scene.frame_start,
    "frame_end": scene.frame_end,
    "sphere_found": False,
    "sphere_name": None,
    "keyframes_z": [],
    "horizontal_travel": 0.0,
    "bounce_count": 0,
    "z_variation": 0.0,
    "z_max_decay": False,
    "object_count": len(bpy.data.objects)
}

# Find the sphere
sphere_obj = None
for obj in bpy.data.objects:
    # Check name or mesh data type
    is_sphere_name = "sphere" in obj.name.lower() or "ball" in obj.name.lower()
    is_sphere_mesh = obj.type == 'MESH' and len(obj.data.vertices) > 20 # Simple cube has 8
    
    if is_sphere_name or (is_sphere_mesh and obj.name != "BaseCube" and obj.name != "Ground"):
        sphere_obj = obj
        result["sphere_found"] = True
        result["sphere_name"] = obj.name
        break

if sphere_obj and sphere_obj.animation_data and sphere_obj.animation_data.action:
    # Analyze F-Curves
    fcurves = sphere_obj.animation_data.action.fcurves
    
    # Find Z location curve (index 2)
    z_curve = None
    x_curve = None
    y_curve = None
    
    for fc in fcurves:
        if fc.data_path == "location":
            if fc.array_index == 2: z_curve = fc
            if fc.array_index == 0: x_curve = fc
            if fc.array_index == 1: y_curve = fc
            
    # Analyze Z curve (Bounces)
    if z_curve:
        keyframes = []
        for kp in z_curve.keyframe_points:
            keyframes.append({"frame": kp.co[0], "value": kp.co[1]})
        
        result["keyframes_z"] = keyframes
        
        # Calculate variation
        values = [k["value"] for k in keyframes]
        if values:
            result["z_variation"] = max(values) - min(values)
            
            # Detect bounces (local minima near ground)
            # We sample the curve to be robust against handle types
            bounces = 0
            prev_slope = 0
            ground_threshold = 1.5  # Generous threshold for ground contact
            
            # Sample frames 1 to 120
            trajectory_z = []
            for f in range(scene.frame_start, scene.frame_end + 1):
                val = z_curve.evaluate(f)
                trajectory_z.append(val)
                
            # Simple peak detection on sampled data
            # Look for valleys where Z < threshold
            in_valley = False
            valley_min = float('inf')
            
            bounce_minima = []
            bounce_maxima = []
            
            # Find local minima (contacts)
            for i in range(1, len(trajectory_z)-1):
                prev = trajectory_z[i-1]
                curr = trajectory_z[i]
                next_val = trajectory_z[i+1]
                
                if curr < prev and curr < next_val and curr < ground_threshold:
                    bounce_minima.append(curr)
                    
                if curr > prev and curr > next_val and curr > ground_threshold:
                    bounce_maxima.append(curr)
            
            result["bounce_count"] = len(bounce_minima)
            
            # Check energy loss (decaying peaks)
            if len(bounce_maxima) >= 2:
                decreasing = True
                for i in range(len(bounce_maxima)-1):
                    if bounce_maxima[i+1] >= bounce_maxima[i]:
                        decreasing = False
                        break
                result["z_max_decay"] = decreasing

    # Calculate horizontal travel
    start_frame = scene.frame_start
    end_frame = scene.frame_end
    
    start_x = x_curve.evaluate(start_frame) if x_curve else sphere_obj.location.x
    end_x = x_curve.evaluate(end_frame) if x_curve else sphere_obj.location.x
    
    start_y = y_curve.evaluate(start_frame) if y_curve else sphere_obj.location.y
    end_y = y_curve.evaluate(end_frame) if y_curve else sphere_obj.location.y
    
    dist = math.sqrt((end_x - start_x)**2 + (end_y - start_y)**2)
    result["horizontal_travel"] = dist

print("JSON_RESULT:" + json.dumps(result))
PYEOF

    # Run analysis
    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    SCENE_ANALYSIS=$(echo "$ANALYSIS_OUTPUT" | grep "^JSON_RESULT:" | sed 's/^JSON_RESULT://' || echo '{"error": "Parse failed"}')
    rm -f "$ANALYSIS_SCRIPT"
fi

# Create final JSON
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "is_valid_blend": $IS_VALID_BLEND,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "analysis": $SCENE_ANALYSIS,
    "screenshot_path": "/tmp/task_end.png"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="