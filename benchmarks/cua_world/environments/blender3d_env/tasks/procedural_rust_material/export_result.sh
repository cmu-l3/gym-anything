#!/bin/bash
echo "=== Exporting procedural_rust_material result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# ================================================================
# CONFIGURATION
# ================================================================
EXPECTED_BLEND="/home/ga/BlenderProjects/rust_bmw.blend"
EXPECTED_RENDER="/home/ga/BlenderProjects/rust_render.png"

# ================================================================
# CHECK BLEND FILE
# ================================================================
BLEND_EXISTS="false"
BLEND_SIZE="0"
BLEND_VALID="false"

if [ -f "$EXPECTED_BLEND" ]; then
    BLEND_EXISTS="true"
    BLEND_SIZE=$(stat -c%s "$EXPECTED_BLEND" 2>/dev/null || echo "0")

    # Check magic bytes for valid blend file
    # Blender 4.x uses zstd compression (magic: 28 b5 2f fd)
    # Blender 3.x uses uncompressed (magic: BLENDER) or gzip (magic: 1f 8b)
    MAGIC=$(head -c 7 "$EXPECTED_BLEND" 2>/dev/null | tr -d '\0')
    MAGIC_HEX=$(xxd -l 4 -p "$EXPECTED_BLEND" 2>/dev/null)
    if [ "$MAGIC" = "BLENDER" ] || [ "$MAGIC_HEX" = "28b52ffd" ] || [ "${MAGIC_HEX:0:4}" = "1f8b" ]; then
        BLEND_VALID="true"
    fi
fi

# ================================================================
# ANALYZE SAVED BLEND FILE FOR SHADER NODES
# ================================================================
SCENE_ANALYSIS='{"error": "no blend file"}'

if [ "$BLEND_EXISTS" = "true" ] && [ "$BLEND_VALID" = "true" ]; then
    ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_material.XXXXXX.py)
    cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import math

bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/rust_bmw.blend")

result = {
    "car_body_found": False,
    "material_found": False,
    "material_name": None,
    "nodes": [],
    "node_types": [],
    "node_count": 0,
    "links": [],
    "link_count": 0,
    "has_noise_texture": False,
    "has_color_ramp": False,
    "has_mix_shader": False,
    "has_voronoi": False,
    "has_bump": False,
    "principled_bsdf_count": 0,
    "noise_params": {},
    "voronoi_params": {},
    "bump_params": {},
    "bsdf_params": [],
    "colorramp_stops": [],
    "render_engine": bpy.context.scene.render.engine,
    "render_samples": getattr(bpy.context.scene.cycles, 'samples', 0)
}

# Find CarBody object
obj = bpy.data.objects.get("CarBody")
if obj is None:
    # Try finding largest mesh as fallback
    for o in bpy.data.objects:
        if o.type == 'MESH':
            if obj is None or len(o.data.vertices) > len(obj.data.vertices):
                obj = o

if obj and obj.type == 'MESH':
    result["car_body_found"] = True

    if obj.data.materials:
        mat = obj.data.materials[0]
        result["material_found"] = True
        result["material_name"] = mat.name

        if mat.use_nodes and mat.node_tree:
            nodes = mat.node_tree.nodes
            links = mat.node_tree.links

            result["node_count"] = len(nodes)
            result["link_count"] = len(links)

            # Catalog all nodes
            for n in nodes:
                node_info = {
                    "name": n.name,
                    "type": n.type,
                    "bl_idname": n.bl_idname
                }
                result["nodes"].append(node_info)
                result["node_types"].append(n.bl_idname)

                # Noise Texture params
                if n.bl_idname == "ShaderNodeTexNoise":
                    result["has_noise_texture"] = True
                    result["noise_params"] = {
                        "scale": round(n.inputs["Scale"].default_value, 2),
                        "detail": round(n.inputs["Detail"].default_value, 2),
                        "roughness": round(n.inputs["Roughness"].default_value, 2)
                    }

                # Color Ramp
                elif n.bl_idname == "ShaderNodeValToRGB":
                    result["has_color_ramp"] = True
                    stops = []
                    for elem in n.color_ramp.elements:
                        stops.append({
                            "position": round(elem.position, 3),
                            "color": [round(c, 3) for c in elem.color]
                        })
                    result["colorramp_stops"] = stops

                # Principled BSDF
                elif n.bl_idname == "ShaderNodeBsdfPrincipled":
                    result["principled_bsdf_count"] += 1
                    bsdf_info = {
                        "name": n.name,
                        "base_color": [round(c, 3) for c in n.inputs["Base Color"].default_value],
                        "metallic": round(n.inputs["Metallic"].default_value, 3),
                        "roughness": round(n.inputs["Roughness"].default_value, 3)
                    }
                    result["bsdf_params"].append(bsdf_info)

                # Mix Shader
                elif n.bl_idname == "ShaderNodeMixShader":
                    result["has_mix_shader"] = True

                # Voronoi Texture
                elif n.bl_idname == "ShaderNodeTexVoronoi":
                    result["has_voronoi"] = True
                    result["voronoi_params"] = {
                        "scale": round(n.inputs["Scale"].default_value, 2)
                    }

                # Bump
                elif n.bl_idname == "ShaderNodeBump":
                    result["has_bump"] = True
                    result["bump_params"] = {
                        "strength": round(n.inputs["Strength"].default_value, 3)
                    }

            # Catalog all links
            for link in links:
                link_info = {
                    "from_node": link.from_node.name,
                    "from_socket": link.from_socket.name,
                    "from_node_type": link.from_node.bl_idname,
                    "to_node": link.to_node.name,
                    "to_socket": link.to_socket.name,
                    "to_node_type": link.to_node.bl_idname
                }
                result["links"].append(link_info)

print("ANALYSIS_JSON:" + json.dumps(result))
PYEOF

    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    ANALYSIS_LINE=$(echo "$ANALYSIS_OUTPUT" | grep '^ANALYSIS_JSON:' | head -1)

    if [ -n "$ANALYSIS_LINE" ]; then
        SCENE_ANALYSIS="${ANALYSIS_LINE#ANALYSIS_JSON:}"
    else
        SCENE_ANALYSIS='{"error": "could not parse blender output"}'
    fi

    rm -f "$ANALYSIS_SCRIPT"
fi

# ================================================================
# CHECK RENDER OUTPUT
# ================================================================
RENDER_EXISTS="false"
RENDER_SIZE="0"
RENDER_WIDTH="0"
RENDER_HEIGHT="0"
RENDER_FORMAT="none"

if [ -f "$EXPECTED_RENDER" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$EXPECTED_RENDER" 2>/dev/null || echo "0")

    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/BlenderProjects/rust_render.png")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "unknown"}))
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "format": "unknown"}))
PYEOF
)
    RENDER_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    RENDER_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    RENDER_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
fi

# ================================================================
# CHECK BLENDER STATE
# ================================================================
BLENDER_RUNNING="false"
BLENDER_WINDOW_TITLE=""

if pgrep -x "blender" > /dev/null 2>&1; then
    BLENDER_RUNNING="true"
fi

BLENDER_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "blender" || echo "")
if [ -n "$BLENDER_WINDOWS" ]; then
    BLENDER_WINDOW_TITLE=$(echo "$BLENDER_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "blend_exists": $BLEND_EXISTS,
    "blend_size_bytes": $BLEND_SIZE,
    "blend_valid": $BLEND_VALID,
    "blend_path": "$EXPECTED_BLEND",
    "render_exists": $RENDER_EXISTS,
    "render_size_bytes": $RENDER_SIZE,
    "render_width": $RENDER_WIDTH,
    "render_height": $RENDER_HEIGHT,
    "render_format": "$RENDER_FORMAT",
    "render_path": "$EXPECTED_RENDER",
    "scene_analysis": $SCENE_ANALYSIS,
    "blender_was_running": $BLENDER_RUNNING,
    "blender_window_title": "$BLENDER_WINDOW_TITLE",
    "screenshot_path": "/tmp/task_end.png",
    "initial_screenshot_path": "/tmp/task_start.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
