#!/bin/bash
# Shared utilities for Blender tasks

# Screenshot function
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Run Blender Python script
run_blender_script() {
    local script="$1"
    local blend_file="${2:-}"

    if [ -n "$blend_file" ]; then
        /opt/blender/blender --background "$blend_file" --python "$script" 2>/dev/null
    else
        /opt/blender/blender --background --python "$script" 2>/dev/null
    fi
}

# Get scene info as JSON
get_scene_info() {
    local blend_file="$1"

    python3 << PYEOF
import subprocess
import json

script = '''
import bpy
import json

# Load the blend file
bpy.ops.wm.open_mainfile(filepath="$blend_file")

scene = bpy.context.scene
info = {
    "scene_name": scene.name,
    "frame_start": scene.frame_start,
    "frame_end": scene.frame_end,
    "frame_current": scene.frame_current,
    "render_engine": scene.render.engine,
    "resolution_x": scene.render.resolution_x,
    "resolution_y": scene.render.resolution_y,
    "object_count": len(bpy.data.objects),
    "mesh_count": len(bpy.data.meshes),
    "material_count": len(bpy.data.materials),
    "camera_count": len([o for o in bpy.data.objects if o.type == "CAMERA"]),
    "light_count": len([o for o in bpy.data.objects if o.type == "LIGHT"]),
    "objects": []
}

for obj in bpy.data.objects:
    obj_info = {
        "name": obj.name,
        "type": obj.type,
        "location": list(obj.location),
        "visible": obj.visible_get()
    }
    info["objects"].append(obj_info)

print(json.dumps(info))
'''

result = subprocess.run(
    ["/opt/blender/blender", "--background", "--python-expr", script],
    capture_output=True,
    text=True
)

# Extract JSON from output (filter out Blender's own output)
for line in result.stdout.split('\n'):
    line = line.strip()
    if line.startswith('{') and line.endswith('}'):
        print(line)
        break
PYEOF
}

# Check if render output exists
check_render_output() {
    local output_path="$1"
    local expected_format="${2:-PNG}"

    if [ -f "$output_path" ]; then
        # Get file info
        local size=$(stat -c%s "$output_path" 2>/dev/null || echo "0")
        local mime=$(file -b --mime-type "$output_path" 2>/dev/null || echo "unknown")

        echo "{\"exists\": true, \"size\": $size, \"mime_type\": \"$mime\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mime_type\": null}"
    fi
}

# Get render output dimensions
get_image_dimensions() {
    local image_path="$1"

    python3 << PYEOF
import json
try:
    from PIL import Image
    img = Image.open("$image_path")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format}))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
}

# Check Blender process status
is_blender_running() {
    if pgrep -x "blender" > /dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

# Get Blender window info
get_blender_window() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "blender" | head -1
}

# Focus Blender window
focus_blender() {
    DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true
}

# Maximize Blender window
maximize_blender() {
    local window_id=$(DISPLAY=:1 wmctrl -l | grep -i "blender" | awk '{print $1}' | head -1)
    if [ -n "$window_id" ]; then
        DISPLAY=:1 wmctrl -i -r "$window_id" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
}
