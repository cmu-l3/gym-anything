#!/bin/bash
echo "=== Exporting Matchmove Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_BLEND="/home/ga/BlenderProjects/tracking_solved.blend"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence
if [ -f "$OUTPUT_BLEND" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_BLEND")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
fi

# Analyze the blend file using Blender's Python API
echo "Analyzing tracking data..."
ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_tracking.XXXXXX.py)
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json

result = {
    "movie_clip_loaded": False,
    "track_count": 0,
    "solve_error": 999.0,
    "is_solved": False,
    "camera_constrained": False,
    "camera_animated": False
}

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/tracking_solved.blend")

    # 1. Check for Movie Clip
    if len(bpy.data.movieclips) > 0:
        clip = bpy.data.movieclips[0]
        result["movie_clip_loaded"] = True
        
        # 2. Check Tracking Data
        tracking = clip.tracking
        if tracking and tracking.tracks:
            # Count valid tracks (must have data)
            valid_tracks = [t for t in tracking.tracks if len(t.markers) > 1]
            result["track_count"] = len(valid_tracks)
            
            # 3. Check Solve Error
            # The 'reconstruction' object holds the solve data
            camera_object = tracking.objects['Camera']
            if camera_object and camera_object.is_camera_object:
                result["solve_error"] = camera_object.reconstruction.average_error
                result["is_solved"] = camera_object.reconstruction.is_valid

    # 4. Check Scene Camera Application
    scene_cam = bpy.context.scene.camera
    if scene_cam:
        # Check for Camera Solver constraint
        for const in scene_cam.constraints:
            if const.type == 'CAMERA_SOLVER':
                result["camera_constrained"] = True
                break
        
        # Check for baked keyframes on the camera
        if scene_cam.animation_data and scene_cam.animation_data.action:
             result["camera_animated"] = True

except Exception as e:
    result["error"] = str(e)

print("JSON_RESULT:" + json.dumps(result))
PYEOF

# Run analysis
ANALYSIS_OUTPUT=$(su - ga -c "/opt/blender/blender --background --python $ANALYSIS_SCRIPT" 2>/dev/null)
JSON_DATA=$(echo "$ANALYSIS_OUTPUT" | grep "^JSON_RESULT:" | sed 's/JSON_RESULT://')

if [ -z "$JSON_DATA" ]; then
    JSON_DATA="{}"
fi

# Clean up
rm -f "$ANALYSIS_SCRIPT"

# Combine into final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "analysis": $JSON_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="