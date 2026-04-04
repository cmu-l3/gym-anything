#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

BLEND_FILE="/home/ga/BlenderProjects/suzanne_checker.blend"
RENDER_FILE="/home/ga/BlenderProjects/checker_render.png"
RESULT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result file
cat > "$RESULT_FILE" << EOF
{
  "blend_file_exists": false,
  "render_file_exists": false,
  "analysis_errors": []
}
EOF

# Analyze the blend file with Blender Python if it exists
if [ -f "$BLEND_FILE" ]; then
    echo "Analyzing blend file..."
    cat > /tmp/analyze_result.py << 'PYEOF'
import bpy
import json
import os
import sys

BLEND_FILE = "/home/ga/BlenderProjects/suzanne_checker.blend"
RENDER_FILE = "/home/ga/BlenderProjects/checker_render.png"
RESULT_FILE = "/tmp/task_result.json"

try:
    task_start = int(open("/tmp/task_start_time.txt").read().strip())
except:
    task_start = 0

result = {
    "blend_file_exists": True,
    "render_file_exists": False,
    "blend_file_valid": False,
    "render_file_size_kb": 0,
    "render_width": 0,
    "render_height": 0,
    "suzanne_uv_layer_count": 0,
    "uv_coverage_ratio": 0.0,
    "has_checker_node": False,
    "checker_connected_to_base_color": False,
    "checker_scale": 0,
    "material_node_types": [],
    "blend_modified_after_start": False,
    "render_modified_after_start": False,
    "analysis_errors": []
}

# Check blend file validity
try:
    with open(BLEND_FILE, 'rb') as f:
        magic = f.read(7)
        result["blend_file_valid"] = (magic == b'BLENDER')
except Exception as e:
    result["analysis_errors"].append(f"File read error: {e}")

blend_mtime = os.path.getmtime(BLEND_FILE)
result["blend_modified_after_start"] = (blend_mtime > task_start)

# Check render file
if os.path.exists(RENDER_FILE):
    result["render_file_exists"] = True
    result["render_file_size_kb"] = os.path.getsize(RENDER_FILE) / 1024
    render_mtime = os.path.getmtime(RENDER_FILE)
    result["render_modified_after_start"] = (render_mtime > task_start)
    
    try:
        # Simple PNG header check if PIL fails
        with open(RENDER_FILE, 'rb') as f:
            header = f.read(8)
            if header == b'\x89PNG\r\n\x1a\n':
                # It's a PNG, try to parse chunks for dimensions if needed
                pass
    except:
        pass

# Open the blend file for scene analysis
try:
    bpy.ops.wm.open_mainfile(filepath=BLEND_FILE)
    
    # Find Suzanne
    suzanne = None
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and 'suzan' in obj.name.lower():
            suzanne = obj
            break
            
    if suzanne:
        mesh = suzanne.data
        
        # 1. Check UV Layers
        result["suzanne_uv_layer_count"] = len(mesh.uv_layers)
        
        # 2. Check UV Coverage
        if len(mesh.uv_layers) > 0:
            uv_layer = mesh.uv_layers.active
            if uv_layer and len(uv_layer.data) > 0:
                min_u, max_u = 1.0, 0.0
                min_v, max_v = 1.0, 0.0
                has_uvs = False
                
                # Sample loops to avoid iterating millions of vertices if dense
                for i, loop in enumerate(mesh.loops):
                    if i % 10 != 0: continue # Sample every 10th
                    uv = uv_layer.data[loop.index].uv
                    u, v = uv[0], uv[1]
                    min_u = min(min_u, u)
                    max_u = max(max_u, u)
                    min_v = min(min_v, v)
                    max_v = max(max_v, v)
                    has_uvs = True
                
                if has_uvs:
                    u_range = max_u - min_u
                    v_range = max_v - min_v
                    result["uv_coverage_ratio"] = round(u_range * v_range, 4)
                    result["uv_min_u"] = min_u
                    result["uv_max_u"] = max_u
                    result["uv_min_v"] = min_v
                    result["uv_max_v"] = max_v

        # 3. Check Material Nodes
        if len(suzanne.data.materials) > 0:
            mat = suzanne.data.materials[0]
            if mat and mat.use_nodes:
                nodes = mat.node_tree.nodes
                result["material_node_types"] = [n.type for n in nodes]
                
                checker_nodes = [n for n in nodes if n.type == 'TEX_CHECKER']
                if checker_nodes:
                    result["has_checker_node"] = True
                    checker = checker_nodes[0]
                    
                    # Check scale
                    if "Scale" in checker.inputs:
                        result["checker_scale"] = checker.inputs["Scale"].default_value
                    
                    # Check connection to Base Color
                    # We look for any path from checker to Principled BSDF Base Color
                    # This handles direct links and simple Mix nodes
                    for link in mat.node_tree.links:
                        if (link.to_node.type == 'BSDF_PRINCIPLED' and 
                            link.to_socket.name == 'Base Color'):
                            
                            # Walk back up
                            src = link.from_node
                            if src == checker:
                                result["checker_connected_to_base_color"] = True
                            elif src.type in ['MIX_RGB', 'MIX_SHADER', 'MAPPING', 'TEX_COORD']:
                                # Shallow check for one level of indirection
                                for l2 in mat.node_tree.links:
                                    if l2.to_node == src and l2.from_node == checker:
                                        result["checker_connected_to_base_color"] = True

    else:
        result["analysis_errors"].append("Suzanne object not found")

except Exception as e:
    result["analysis_errors"].append(f"Blender API error: {e}")

# Save result
with open(RESULT_FILE, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

    # Run analysis script
    /opt/blender/blender --background --python /tmp/analyze_result.py > /dev/null 2>&1 || true
fi

# Ensure permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result generated:"
cat "$RESULT_FILE"
echo "=== Export complete ==="