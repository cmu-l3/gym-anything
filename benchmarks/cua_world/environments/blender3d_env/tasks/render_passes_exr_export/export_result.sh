#!/bin/bash
echo "=== Exporting render_passes_exr_export result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
BLEND_FILE="/home/ga/BlenderProjects/bmw_vfx_setup.blend"
EXR_FILE="/home/ga/BlenderProjects/bmw_passes.exr"
RESULT_FILE="/tmp/task_result.json"
START_TIME_FILE="/tmp/task_start_time.txt"

# Get task start time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
else
    TASK_START=0
fi

# Python script to analyze the SAVED blend file and check the EXR
cat > /tmp/analyze_result.py << 'PYEOF'
import bpy
import json
import os
import sys
import struct

blend_path = sys.argv[sys.argv.index("--") + 1]
exr_path = sys.argv[sys.argv.index("--") + 2]
task_start = float(sys.argv[sys.argv.index("--") + 3])

result = {
    "blend_exists": False,
    "exr_exists": False,
    "exr_valid": False,
    "exr_size_kb": 0,
    "exr_fresh": False,
    "passes": {},
    "output_settings": {}
}

# 1. Analyze Blend File
if os.path.exists(blend_path):
    result["blend_exists"] = True
    try:
        bpy.ops.wm.open_mainfile(filepath=blend_path)
        scene = bpy.context.scene
        vl = scene.view_layers[0]

        # Check Passes
        result["passes"] = {
            "use_pass_z": vl.use_pass_z,
            "use_pass_mist": vl.use_pass_mist,
            "use_pass_normal": vl.use_pass_normal,
            "use_pass_diffuse_color": vl.use_pass_diffuse_color,
            "use_pass_glossy_direct": vl.use_pass_glossy_direct,
            "use_pass_ambient_occlusion": vl.use_pass_ambient_occlusion
        }

        # Check Output Settings
        result["output_settings"] = {
            "file_format": scene.render.image_settings.file_format,
            "color_depth": scene.render.image_settings.color_depth
        }
    except Exception as e:
        result["blend_error"] = str(e)

# 2. Analyze EXR File
if os.path.exists(exr_path):
    result["exr_exists"] = True
    stat = os.stat(exr_path)
    result["exr_size_kb"] = stat.st_size / 1024
    result["exr_fresh"] = stat.st_mtime > task_start

    # Check Magic Bytes (0x76 0x2f 0x31 0x01)
    try:
        with open(exr_path, 'rb') as f:
            magic = f.read(4)
            # Little endian integer 20000630
            if magic == b'\x76\x2f\x31\x01':
                result["exr_valid"] = True
    except:
        pass

print("JSON_RESULT:" + json.dumps(result))
PYEOF

# Run analysis headless
# We suppress stdout except for our JSON line
OUTPUT=$(/opt/blender/blender --background --python /tmp/analyze_result.py -- "$BLEND_FILE" "$EXR_FILE" "$TASK_START" 2>&1)

# Extract JSON
echo "$OUTPUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://' > "$RESULT_FILE"

# Make readable
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="