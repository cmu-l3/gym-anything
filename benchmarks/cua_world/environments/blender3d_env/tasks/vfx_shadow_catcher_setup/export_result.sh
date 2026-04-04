#!/bin/bash
echo "=== Exporting VFX Shadow Catcher Result ==="

source /workspace/scripts/task_utils.sh

# Output Paths
OUTPUT_BLEND="/home/ga/BlenderProjects/shadow_setup.blend"
OUTPUT_RENDER="/home/ga/BlenderProjects/shadow_composite.png"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Capture final screen
take_screenshot /tmp/task_final.png ga

# Check file existence
BLEND_EXISTS="false"
RENDER_EXISTS="false"
[ -f "$OUTPUT_BLEND" ] && BLEND_EXISTS="true"
[ -f "$OUTPUT_RENDER" ] && RENDER_EXISTS="true"

# ==============================================================================
# INSPECT BLEND FILE (Headless Blender)
# ==============================================================================
echo "Inspecting blend file settings..."
INSPECT_SCRIPT=$(mktemp /tmp/inspect_vfx.XXXXXX.py)
cat > "$INSPECT_SCRIPT" << 'PYEOF'
import bpy
import json
import sys

try:
    # Open the file if it exists
    filepath = "/home/ga/BlenderProjects/shadow_setup.blend"
    bpy.ops.wm.open_mainfile(filepath=filepath)
    
    scene = bpy.context.scene
    
    # Check GroundPlane properties
    ground = bpy.data.objects.get("GroundPlane")
    is_shadow_catcher = ground.is_shadow_catcher if ground else False
    
    # Check Render properties
    engine = scene.render.engine
    film_transparent = scene.render.film_transparent
    
    result = {
        "valid_file": True,
        "engine": engine,
        "film_transparent": film_transparent,
        "ground_exists": ground is not None,
        "is_shadow_catcher": is_shadow_catcher
    }
except Exception as e:
    result = {
        "valid_file": False,
        "error": str(e)
    }

print("JSON_RESULT:" + json.dumps(result))
PYEOF

BLEND_DATA="{}"
if [ "$BLEND_EXISTS" = "true" ]; then
    # Run inspection
    INSPECT_OUT=$(/opt/blender/blender --background --python "$INSPECT_SCRIPT" 2>/dev/null)
    # Extract JSON
    BLEND_DATA=$(echo "$INSPECT_OUT" | grep "JSON_RESULT:" | sed 's/JSON_RESULT://')
fi
if [ -z "$BLEND_DATA" ]; then BLEND_DATA="{\"valid_file\": false}"; fi
rm -f "$INSPECT_SCRIPT"

# ==============================================================================
# INSPECT RENDER OUTPUT (Python/PIL)
# ==============================================================================
echo "Inspecting rendered image..."
IMAGE_DATA="{}"
if [ "$RENDER_EXISTS" = "true" ]; then
    ANALYZE_IMG_SCRIPT=$(mktemp /tmp/analyze_img.XXXXXX.py)
    cat > "$ANALYZE_IMG_SCRIPT" << 'PYEOF'
import json
import sys
from PIL import Image
import numpy as np

try:
    img_path = "/home/ga/BlenderProjects/shadow_composite.png"
    img = Image.open(img_path)
    
    width, height = img.size
    mode = img.mode
    
    # Verify Alpha Channel
    has_alpha = 'A' in mode
    
    # Analysis logic:
    # 1. Corner pixels should be transparent (Alpha=0) if film transparent worked
    # 2. Center pixels (Car) should be opaque (Alpha=255)
    # 3. Pixels under car (Shadow) should be semi-transparent (0 < Alpha < 255)
    
    corners = [
        (0, 0), (width-1, 0), (0, height-1), (width-1, height-1)
    ]
    
    # Convert to RGBA if not already
    img = img.convert("RGBA")
    pixels = img.load()
    
    # Check background transparency
    bg_transparent_count = 0
    for x, y in corners:
        if pixels[x, y][3] < 10: # Allow small noise
            bg_transparent_count += 1
            
    is_background_transparent = bg_transparent_count >= 3
    
    # Check for shadow presence (histogram of alpha)
    # We expect some pixels to have partial alpha (shadows)
    # Opaque: > 250
    # Transparent: < 10
    # Shadow: 10 - 250
    
    alpha_channel = np.array(img)[:, :, 3]
    total_pixels = alpha_channel.size
    
    opaque_pixels = np.sum(alpha_channel > 250)
    transparent_pixels = np.sum(alpha_channel < 10)
    shadow_pixels = np.sum((alpha_channel >= 10) & (alpha_channel <= 250))
    
    result = {
        "exists": True,
        "width": width,
        "height": height,
        "mode": mode,
        "is_background_transparent": is_background_transparent,
        "has_opaque_subject": int(opaque_pixels) > 100,
        "has_shadow_pixels": int(shadow_pixels) > 100, # At least some shadow
        "shadow_pixel_count": int(shadow_pixels)
    }

except Exception as e:
    result = {
        "exists": False,
        "error": str(e)
    }

print("JSON_IMG:" + json.dumps(result))
PYEOF

    IMG_OUT=$(python3 "$ANALYZE_IMG_SCRIPT")
    IMAGE_DATA=$(echo "$IMG_OUT" | grep "JSON_IMG:" | sed 's/JSON_IMG://')
    rm -f "$ANALYZE_IMG_SCRIPT"
fi
if [ -z "$IMAGE_DATA" ]; then IMAGE_DATA="{\"exists\": false}"; fi

# ==============================================================================
# COMPILE RESULT
# ==============================================================================
cat > /tmp/task_result.json << EOF
{
    "blend_exists": $BLEND_EXISTS,
    "render_exists": $RENDER_EXISTS,
    "blend_data": $BLEND_DATA,
    "image_data": $IMAGE_DATA,
    "timestamp": $(date +%s)
}
EOF

# Safe copy to avoid permission issues
cp /tmp/task_result.json /tmp/final_result.json
chmod 666 /tmp/final_result.json

echo "Export complete. Result:"
cat /tmp/final_result.json