#!/bin/bash
echo "=== Exporting Character Leg IK Rig Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# File paths
OUTPUT_FILE="/home/ga/BlenderProjects/leg_rig_completed.blend"
RESULT_JSON="/tmp/task_result.json"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if output file exists
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "{\"error\": \"Output file not found\", \"file_exists\": false}" > "$RESULT_JSON"
    exit 0
fi

# Check timestamp (anti-gaming)
FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
if [ "$FILE_MTIME" -le "$TASK_START_TIME" ]; then
    echo "{\"error\": \"File not modified during task\", \"file_exists\": true, \"modified\": false}" > "$RESULT_JSON"
    exit 0
fi

# ==============================================================================
# ANALYZE RIG WITH BLENDER PYTHON
# ==============================================================================
# We run a script inside Blender to inspect the armature, constraints, and pose.
cat > /tmp/analyze_rig.py << 'PYEOF'
import bpy
import json
import math
import sys

# Open the submitted file
try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/leg_rig_completed.blend")
except:
    print(json.dumps({"error": "Failed to open blend file", "valid_blend": False}))
    sys.exit(0)

result = {
    "valid_blend": True,
    "armature_found": False,
    "constraint_found": False,
    "constraint_type": None,
    "target_obj": None,
    "subtarget_bone": None,
    "pole_target_obj": None,
    "pole_subtarget_bone": None,
    "chain_length": 0,
    "knee_bent": False,
    "knee_displacement": 0.0
}

# Find armature
arm_obj = bpy.data.objects.get("LegRig")
if arm_obj and arm_obj.type == 'ARMATURE':
    result["armature_found"] = True
    
    # Check Shin.L constraints
    shin_bone = arm_obj.pose.bones.get("Shin.L")
    if shin_bone:
        for c in shin_bone.constraints:
            if c.type == 'IK':
                result["constraint_found"] = True
                result["constraint_type"] = c.type
                result["target_obj"] = c.target.name if c.target else None
                result["subtarget_bone"] = c.subtarget
                result["pole_target_obj"] = c.pole_target.name if c.pole_target else None
                result["pole_subtarget_bone"] = c.pole_subtarget
                result["chain_length"] = c.chain_count
                break
    
    # Check if knee is bent (posed)
    # We compare the PoseBone head location to the Rest Bone head location
    # Note: PoseBone matrices are in Object Space.
    # Rest bones (EditBones) are not directly accessible in Pose mode easily without mode switch,
    # but arm_obj.data.bones contains rest data relative to armature origin.
    
    if shin_bone:
        # Get current pose head position (Object space)
        pose_head = shin_bone.head
        
        # Get rest head position (Local/Object space since armature is at 0,0,0)
        rest_bone = arm_obj.data.bones.get("Shin.L")
        if rest_bone:
            rest_head = rest_bone.head_local
            
            # Calculate displacement distance
            diff = (pose_head - rest_head).length
            result["knee_displacement"] = round(diff, 4)
            
            # Threshold: if moved more than 0.01 units, it's bent/posed
            if diff > 0.01:
                result["knee_bent"] = True

print(json.dumps(result))
PYEOF

# Run analysis
/opt/blender/blender --background --python /tmp/analyze_rig.py > /tmp/blender_analysis.log 2>&1

# Extract JSON from log (last line typically)
tail -n 1 /tmp/blender_analysis.log > "$RESULT_JSON"

# Fallback if extraction failed
if ! grep -q "valid_blend" "$RESULT_JSON"; then
    echo "{\"error\": \"Analysis script failed\", \"logs\": \"$(tail -n 5 /tmp/blender_analysis.log | tr '\n' ' ')\"}" > "$RESULT_JSON"
fi

# Add file info
# We use jq-like logic or python to merge, but simpler here just to output what we got
# The verifier handles the structure.

echo "Export complete. Result:"
cat "$RESULT_JSON"