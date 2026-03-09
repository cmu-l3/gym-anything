#!/bin/bash
echo "=== Exporting Rack Focus Animation results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
BLEND_FILE="/home/ga/BlenderProjects/rack_focus.blend"
FRAME01="/home/ga/BlenderProjects/rack_focus_frame01.png"
FRAME60="/home/ga/BlenderProjects/rack_focus_frame60.png"
RESULT_FILE="/tmp/task_result.json"

# Check files existence
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local size=$(stat -c%s "$path" 2>/dev/null || echo "0")
        local mtime=$(stat -c%Y "$path" 2>/dev/null || echo "0")
        local created_in_task="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_in_task="true"
        fi
        echo "{\"exists\": true, \"size_bytes\": $size, \"created_during_task\": $created_in_task}"
    else
        echo "{\"exists\": false, \"size_bytes\": 0, \"created_during_task\": false}"
    fi
}

BLEND_INFO=$(check_file "$BLEND_FILE")
FRAME01_INFO=$(check_file "$FRAME01")
FRAME60_INFO=$(check_file "$FRAME60")

# Analyze the blend file using Blender Python
SCENE_DATA="{}"
if [ -f "$BLEND_FILE" ]; then
    echo "Analyzing saved blend file..."
    
    # Create analysis script
    cat > /tmp/analyze_rack_focus.py << 'PYEOF'
import bpy
import json
import sys

# Open the file
blend_file = sys.argv[sys.argv.index("--") + 1]
try:
    bpy.ops.wm.open_mainfile(filepath=blend_file)
except:
    print("RESULT_JSON:{\"error\": "could not open file"}")
    sys.exit(0)

scene = bpy.context.scene

# Find camera
camera = None
for obj in bpy.data.objects:
    if obj.type == 'CAMERA' and "RackFocusCam" in obj.name:
        camera = obj
        break
if not camera:
    camera = scene.camera

cam_data = {
    "found": False,
    "dof_enabled": False,
    "fstop": 0.0,
    "keyframes": []
}

if camera and camera.type == 'CAMERA':
    cam_data["found"] = True
    cam_data["dof_enabled"] = camera.data.dof.use_dof
    cam_data["fstop"] = camera.data.dof.aperture_fstop
    
    # Check keyframes on focus distance
    # Animation data can be on Object or Data (Camera properties are on Data)
    anim_data = camera.data.animation_data
    if anim_data and anim_data.action:
        for fcurve in anim_data.action.fcurves:
            if 'focus_distance' in fcurve.data_path:
                for kp in fcurve.keyframe_points:
                    cam_data["keyframes"].append({
                        "frame": kp.co[0],
                        "value": kp.co[1]
                    })
    
    # Also check object level just in case user animated custom props
    if not cam_data["keyframes"] and camera.animation_data and camera.animation_data.action:
        for fcurve in camera.animation_data.action.fcurves:
             if 'focus_distance' in fcurve.data_path:
                for kp in fcurve.keyframe_points:
                    cam_data["keyframes"].append({
                        "frame": kp.co[0],
                        "value": kp.co[1]
                    })

    # Evaluate focus at specific frames
    scene.frame_set(1)
    cam_data["focus_at_1"] = camera.data.dof.focus_distance
    
    scene.frame_set(60)
    cam_data["focus_at_60"] = camera.data.dof.focus_distance

result = {
    "frame_start": scene.frame_start,
    "frame_end": scene.frame_end,
    "camera": cam_data
}

print("RESULT_JSON:" + json.dumps(result))
PYEOF

    # Run analysis
    ANALYSIS_OUT=$(/opt/blender/blender --background --python /tmp/analyze_rack_focus.py -- "$BLEND_FILE" 2>&1)
    SCENE_DATA=$(echo "$ANALYSIS_OUT" | grep "^RESULT_JSON:" | sed 's/^RESULT_JSON://')
    
    if [ -z "$SCENE_DATA" ]; then
        SCENE_DATA="{\"error\": \"Parser failed\"}"
    fi
fi

# Construct Final JSON
cat > "$RESULT_FILE" << JSONEOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "blend_file": $BLEND_INFO,
    "frame01": $FRAME01_INFO,
    "frame60": $FRAME60_INFO,
    "scene_analysis": $SCENE_DATA
}
JSONEOF

# Secure output
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Export complete. Result:"
cat "$RESULT_FILE"