#!/bin/bash
echo "=== Exporting product_exploded_view_animation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_BLEND="/home/ga/BlenderProjects/exploded_view.blend"
OUTPUT_RENDER="/home/ga/BlenderProjects/exploded_view.png"

# ================================================================
# CHECK FILES
# ================================================================
BLEND_EXISTS="false"
RENDER_EXISTS="false"
RENDER_SIZE="0"
BLEND_CREATED="false"

if [ -f "$OUTPUT_BLEND" ]; then
    BLEND_EXISTS="true"
    # Basic modification check (if mtime > start time)
    START_TIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('task_start_time', 0))" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_BLEND" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        BLEND_CREATED="true"
    fi
fi

if [ -f "$OUTPUT_RENDER" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$OUTPUT_RENDER" 2>/dev/null || echo "0")
fi

# ================================================================
# ANALYZE SCENE ANIMATION
# ================================================================
ANALYSIS_JSON='{"error": "Analysis failed or file missing"}'

if [ "$BLEND_EXISTS" = "true" ]; then
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_anim.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/exploded_view.blend")
    
    parts = ["Case_Top", "Circuit_Board", "Battery", "Case_Bottom"]
    
    # Check object existence
    existing_parts = [p for p in parts if p in bpy.data.objects]
    
    # Check Animation Data Existence
    has_anim_data = {}
    for p in existing_parts:
        obj = bpy.data.objects[p]
        has_anim = False
        if obj.animation_data and obj.animation_data.action:
            # Check if there are keyframes
            if len(obj.animation_data.action.fcurves) > 0:
                has_anim = True
        has_anim_data[p] = has_anim

    # Get Positions at Frame 1
    bpy.context.scene.frame_set(1)
    pos_frame_1 = {}
    for p in existing_parts:
        pos_frame_1[p] = bpy.data.objects[p].location.z

    # Get Positions at Frame 48
    bpy.context.scene.frame_set(48)
    pos_frame_48 = {}
    for p in existing_parts:
        pos_frame_48[p] = bpy.data.objects[p].location.z

    # Get Scene Info
    frame_end = bpy.context.scene.frame_end

    result = {
        "existing_parts": existing_parts,
        "has_anim_data": has_anim_data,
        "pos_frame_1": pos_frame_1,
        "pos_frame_48": pos_frame_48,
        "frame_end": frame_end,
        "analysis_success": True
    }
    print("JSON_RESULT:" + json.dumps(result))

except Exception as e:
    print("JSON_RESULT:" + json.dumps({"analysis_success": False, "error": str(e)}))
PYEOF

    # Run analysis
    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    # Extract JSON line
    PARSED_JSON=$(echo "$ANALYSIS_OUTPUT" | grep "^JSON_RESULT:" | sed 's/^JSON_RESULT://')
    
    if [ -n "$PARSED_JSON" ]; then
        ANALYSIS_JSON="$PARSED_JSON"
    fi
    rm -f "$ANALYSIS_SCRIPT"
fi

# ================================================================
# COMPILE RESULT
# ================================================================
cat > /tmp/task_result.json << EOF
{
    "blend_exists": $BLEND_EXISTS,
    "blend_created_during_task": $BLEND_CREATED,
    "render_exists": $RENDER_EXISTS,
    "render_size": $RENDER_SIZE,
    "scene_analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json