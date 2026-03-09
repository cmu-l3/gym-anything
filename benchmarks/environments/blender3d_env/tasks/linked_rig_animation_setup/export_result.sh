#!/bin/bash
echo "=== Exporting Linked Rig Animation Result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/BlenderProjects/shot_01_animated.blend"
MASTER_RIG_PATH="/home/ga/BlenderProjects/assets/master_rig.blend"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Run Blender Python analysis
# We need to inspect:
# 1. Is the rig linked?
# 2. Is there a library override?
# 3. Is there animation data?
# 4. Is the pose changed?

cat > /tmp/analyze_rig.py << 'PYEOF'
import bpy
import json
import math
import os

result = {
    "rig_found": False,
    "is_linked": False,
    "is_appended": False,
    "has_override": False,
    "is_posed": False,
    "has_keyframes": False,
    "bone_rotation": 0.0
}

try:
    # Open the student's file
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/shot_01_animated.blend")
    
    # Find the armature
    # We look for an object that is an Armature
    rig_obj = None
    for obj in bpy.data.objects:
        if obj.type == 'ARMATURE':
            rig_obj = obj
            break
            
    if rig_obj:
        result["rig_found"] = True
        
        # Check Link vs Append status
        # If Linked directly: obj.library is not None
        # If Appended: obj.library is None, obj.override_library is None
        # If Linked + Override: obj.override_library is not None
        
        if rig_obj.override_library:
            result["has_override"] = True
            # If overridden, it technically counts as linked for our purpose
            # Check reference to confirm source
            if rig_obj.override_library.reference and rig_obj.override_library.reference.library:
                result["is_linked"] = True
                
        elif rig_obj.library:
            result["is_linked"] = True
            result["has_override"] = False
        else:
            # It's local data (Appended or created from scratch)
            result["is_appended"] = True
            result["is_linked"] = False

        # Check Animation
        if rig_obj.animation_data and rig_obj.animation_data.action:
            if len(rig_obj.animation_data.action.fcurves) > 0:
                result["has_keyframes"] = True

        # Check Pose
        # We know the rest pose from setup_task.sh (UpperArm up, Forearm sideways)
        # Check if Forearm or UpperArm rotation is non-zero in Pose mode
        # Since we are in OBJECT mode usually when opening, data should be accessible
        
        # Ensure we are in Pose mode to read current pose properly? 
        # Actually pose.bones stores the current state relative to rest
        if rig_obj.pose:
            # Check rotation of bones
            total_rot_diff = 0.0
            for pbone in rig_obj.pose.bones:
                # Check rotation modes (QUATERNION, XYZ, etc)
                # Just summing absolute values of rotation components is a rough heuristic
                # but sufficient to detect "did they move it?"
                if pbone.rotation_mode == 'QUATERNION':
                    # Identity is (1, 0, 0, 0)
                    total_rot_diff += abs(pbone.rotation_quaternion[0] - 1.0)
                    total_rot_diff += sum([abs(x) for x in pbone.rotation_quaternion[1:]])
                else:
                    # Euler
                    total_rot_diff += sum([abs(x) for x in pbone.rotation_euler])
            
            result["bone_rotation"] = total_rot_diff
            if total_rot_diff > 0.1: # Threshold for "moved"
                result["is_posed"] = True

except Exception as e:
    result["error"] = str(e)

print("JSON_RESULT:" + json.dumps(result))
PYEOF

# Run analysis
ANALYSIS_JSON="{}"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    RAW_OUT=$(/opt/blender/blender --background --python /tmp/analyze_rig.py 2>/dev/null)
    ANALYSIS_JSON=$(echo "$RAW_OUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
fi

# Clean up temp script
rm -f /tmp/analyze_rig.py

# Combine into final result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "analysis": $ANALYSIS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="