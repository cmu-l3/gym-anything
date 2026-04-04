#!/bin/bash
echo "=== Exporting VSE Rough Cut Assembly results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

PROJECTS_DIR="/home/ga/BlenderProjects"
BLEND_FILE="$PROJECTS_DIR/video_edit.blend"
RENDER_OUTPUT="$PROJECTS_DIR/final_edit.mp4"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# ================================================================
# CHECK FILES
# ================================================================

# Check Blend File
BLEND_EXISTS="false"
BLEND_VALID="false"
BLEND_MTIME="0"
BLEND_SIZE="0"

if [ -f "$BLEND_FILE" ]; then
    BLEND_EXISTS="true"
    BLEND_SIZE=$(stat -c%s "$BLEND_FILE" 2>/dev/null || echo "0")
    BLEND_MTIME=$(stat -c%Y "$BLEND_FILE" 2>/dev/null || echo "0")
    # Check magic bytes
    if [[ "$(head -c 7 "$BLEND_FILE" 2>/dev/null)" == "BLENDER" ]]; then
        BLEND_VALID="true"
    fi
fi

# Check Render Output
RENDER_EXISTS="false"
RENDER_VALID="false"
RENDER_MTIME="0"
RENDER_SIZE="0"
RENDER_DURATION="0.0"

if [ -f "$RENDER_OUTPUT" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$RENDER_OUTPUT" 2>/dev/null || echo "0")
    RENDER_MTIME=$(stat -c%Y "$RENDER_OUTPUT" 2>/dev/null || echo "0")
    
    # Use ffprobe to validate and get duration
    PROBE_DATA=$(ffprobe -v quiet -print_format json -show_format -show_streams "$RENDER_OUTPUT" 2>/dev/null)
    if [ -n "$PROBE_DATA" ]; then
        RENDER_DURATION=$(echo "$PROBE_DATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('format', {}).get('duration', '0.0'))" 2>/dev/null || echo "0.0")
        
        # Check if duration > 0.5s to be considered valid video
        IS_VALID=$(python3 -c "print('true' if float($RENDER_DURATION) > 0.5 else 'false')" 2>/dev/null)
        if [ "$IS_VALID" == "true" ] && [ "$RENDER_SIZE" -gt 10000 ]; then
            RENDER_VALID="true"
        fi
    fi
fi

# ================================================================
# ANALYZE VSE CONTENTS (BLENDER PYTHON)
# ================================================================
echo "Analyzing VSE contents..."

cat > /tmp/analyze_vse.py << 'PYEOF'
import bpy
import json
import os
import sys

# Helper to avoid error if file not found
try:
    blend_path = sys.argv[-1]
    if os.path.exists(blend_path) and blend_path.endswith('.blend'):
        bpy.ops.wm.open_mainfile(filepath=blend_path)
except:
    pass

scene = bpy.context.scene
sequencer = scene.sequence_editor

result = {
    "strip_count": 0,
    "movie_strips": [],
    "transition_strips": [],
    "text_strips": [],
    "frame_range": [scene.frame_start, scene.frame_end],
    "render_resolution": [scene.render.resolution_x, scene.render.resolution_y],
    "fps": scene.render.fps
}

if sequencer and sequencer.sequences:
    result["strip_count"] = len(sequencer.sequences)
    
    for s in sequencer.sequences:
        if s.type == 'MOVIE':
            filepath = s.filepath if hasattr(s, 'filepath') else ""
            result["movie_strips"].append({
                "name": s.name,
                "channel": s.channel,
                "start_frame": s.frame_final_start,
                "filepath": filepath
            })
        elif s.type in ['CROSS', 'GAMMA_CROSS']:
            result["transition_strips"].append({
                "name": s.name,
                "type": s.type,
                "start_frame": s.frame_final_start
            })
        elif s.type == 'TEXT':
            result["text_strips"].append({
                "name": s.name,
                "text": s.text,
                "start_frame": s.frame_final_start
            })

# Sort movie strips by start frame to check sequencing
result["movie_strips"].sort(key=lambda x: x["start_frame"])

print("JSON_RESULT:" + json.dumps(result))
PYEOF

VSE_ANALYSIS="{}"
if [ "$BLEND_VALID" == "true" ]; then
    VSE_OUTPUT=$(/opt/blender/blender --background "$BLEND_FILE" --python /tmp/analyze_vse.py -- "$BLEND_FILE" 2>/dev/null || echo "")
    PARSED_JSON=$(echo "$VSE_OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
    if [ -n "$PARSED_JSON" ]; then
        VSE_ANALYSIS="$PARSED_JSON"
    fi
fi

# ================================================================
# WRITE RESULT JSON
# ================================================================
python3 << PYEOF
import json
import os

try:
    vse_data = json.loads('''$VSE_ANALYSIS''')
except:
    vse_data = {}

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "blend_file": {
        "exists": $BLEND_EXISTS,
        "valid": $BLEND_VALID,
        "mtime": $BLEND_MTIME,
        "size": $BLEND_SIZE
    },
    "render_output": {
        "exists": $RENDER_EXISTS,
        "valid": $RENDER_VALID,
        "mtime": $RENDER_MTIME,
        "size": $RENDER_SIZE,
        "duration": float("$RENDER_DURATION")
    },
    "vse_data": vse_data
}

with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="