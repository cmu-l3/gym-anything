#!/bin/bash
echo "=== Exporting NLA Camera Shake Layering result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_BLEND="/home/ga/BlenderProjects/nla_camera_composite.blend"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"

# Check file existence and timestamp
if [ -f "$OUTPUT_BLEND" ]; then
    OUTPUT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT_BLEND" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# ================================================================
# ANALYZE BLEND FILE WITH PYTHON
# ================================================================
# We need to inspect:
# 1. NLA Tracks on the Camera object
# 2. Strips on those tracks (names and blend modes)
# 3. Evaluate the animation to prove both actions are contributing

ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_nla.XXXXXX.py)
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import sys

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/nla_camera_composite.blend")
except:
    print(json.dumps({"error": "Could not open file"}))
    sys.exit(0)

scene = bpy.context.scene
cam = scene.camera

result = {
    "has_camera": cam is not None,
    "nla_track_count": 0,
    "tracks": [],
    "evaluation": {}
}

if cam and cam.animation_data:
    # 1. Inspect NLA Tracks
    if cam.animation_data.nla_tracks:
        result["nla_track_count"] = len(cam.animation_data.nla_tracks)
        
        for i, track in enumerate(cam.animation_data.nla_tracks):
            track_info = {
                "name": track.name,
                "index": i,
                "strips": []
            }
            for strip in track.strips:
                track_info["strips"].append({
                    "name": strip.name,
                    "action": strip.action.name if strip.action else "None",
                    "blend_type": strip.blend_type,
                    "frame_start": strip.frame_start,
                    "frame_end": strip.frame_end
                })
            result["tracks"].append(track_info)

    # 2. Evaluate Animation (Proof of layering)
    # Frame 1 (Start)
    scene.frame_set(1)
    loc_1 = list(cam.location)
    rot_1 = list(cam.rotation_euler)
    
    # Frame 50 (Middle - Dolly should be at ~5.0, Shake should be active)
    scene.frame_set(50)
    loc_50 = list(cam.location)
    rot_50 = list(cam.rotation_euler)
    
    result["evaluation"] = {
        "frame_1": {"loc": loc_1, "rot": rot_1},
        "frame_50": {"loc": loc_50, "rot": rot_50}
    }

print("JSON_RESULT:" + json.dumps(result))
PYEOF

# Run analysis
PYTHON_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
JSON_DATA=$(echo "$PYTHON_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')

# Fallback if analysis failed
if [ -z "$JSON_DATA" ]; then
    JSON_DATA='{"error": "Analysis script failed or produced no output"}'
fi

rm -f "$ANALYSIS_SCRIPT"

# Combine everything into final result
cat > /tmp/task_result.json << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "analysis": $JSON_DATA,
    "screenshot": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json