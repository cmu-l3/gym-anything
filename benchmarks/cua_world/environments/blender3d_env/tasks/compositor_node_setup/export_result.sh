#!/bin/bash
set -e
echo "=== Exporting compositor task results ==="

source /workspace/scripts/task_utils.sh

PROJECTS_DIR="/home/ga/BlenderProjects"
BLEND_FILE="$PROJECTS_DIR/compositing_setup.blend"
RENDER_FILE="$PROJECTS_DIR/cinematic_composite.png"
RESULT_FILE="/tmp/task_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Check blend file ---
BLEND_EXISTS="false"
BLEND_VALID="false"
BLEND_SIZE_KB=0

if [ -f "$BLEND_FILE" ]; then
    BLEND_EXISTS="true"
    BLEND_SIZE=$(stat -c%s "$BLEND_FILE" 2>/dev/null || echo "0")
    BLEND_SIZE_KB=$((BLEND_SIZE / 1024))
    BLEND_MTIME=$(stat -c%Y "$BLEND_FILE" 2>/dev/null || echo "0")

    # Check magic bytes
    MAGIC=$(head -c 7 "$BLEND_FILE" 2>/dev/null || echo "")
    if [ "$MAGIC" = "BLENDER" ]; then
        BLEND_VALID="true"
    fi
fi

# --- Check render output ---
RENDER_EXISTS="false"
RENDER_SIZE_KB=0
RENDER_WIDTH=0
RENDER_HEIGHT=0
RENDER_TIME=0

if [ -f "$RENDER_FILE" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$RENDER_FILE" 2>/dev/null || echo "0")
    RENDER_SIZE_KB=$((RENDER_SIZE / 1024))
    RENDER_TIME=$(stat -c%Y "$RENDER_FILE" 2>/dev/null || echo "0")

    # Get dimensions via Python
    DIMS=$(python3 -c "
import sys
try:
    from PIL import Image
    img = Image.open('$RENDER_FILE')
    print(f'{img.width} {img.height}')
except:
    print('0 0')
" 2>/dev/null || echo "0 0")
    RENDER_WIDTH=$(echo $DIMS | cut -d' ' -f1)
    RENDER_HEIGHT=$(echo $DIMS | cut -d' ' -f2)
fi

# --- Analyze compositor node tree from blend file ---
# We run a python script inside Blender to traverse the node tree
if [ "$BLEND_VALID" = "true" ]; then
    echo "Analyzing compositor node tree..."

    cat > /tmp/analyze_compositor.py << 'ANALYZE_EOF'
import bpy
import json
import sys

try:
    blend_path = sys.argv[sys.argv.index("--") + 1]
    bpy.ops.wm.open_mainfile(filepath=blend_path)

    scene = bpy.context.scene
    result = {
        "compositor_enabled": scene.use_nodes,
        "glare_node": {"exists": False, "type": None, "threshold": None},
        "color_balance_node": {"exists": False},
        "lens_distortion_node": {"exists": False, "distortion": None},
        "nodes_connected_chain": False,
        "chain_details": {},
        "total_compositor_nodes": 0
    }

    if scene.use_nodes and scene.node_tree:
        nodes = scene.node_tree.nodes
        links = scene.node_tree.links

        result["total_compositor_nodes"] = len(nodes)

        # Record all nodes
        for node in nodes:
            # Check Glare node
            if node.bl_idname == "CompositorNodeGlare":
                result["glare_node"]["exists"] = True
                result["glare_node"]["type"] = node.glare_type
                result["glare_node"]["threshold"] = node.threshold

            # Check Color Balance node
            if node.bl_idname == "CompositorNodeColorBalance":
                result["color_balance_node"]["exists"] = True
                result["color_balance_node"]["correction_method"] = node.correction_method

            # Check Lens Distortion node
            if node.bl_idname == "CompositorNodeLensdist":
                result["lens_distortion_node"]["exists"] = True
                # Handle inputs that might be linked or values
                dist_input = node.inputs.get("Distortion")
                if dist_input:
                    result["lens_distortion_node"]["distortion"] = dist_input.default_value if not dist_input.is_linked else "linked"

        # --- Verify connected chain ---
        # Build adjacency graph
        adjacency = {}
        for link in links:
            if not link.from_node or not link.to_node: continue
            from_n = link.from_node.name
            to_n = link.to_node.name
            if from_n not in adjacency: adjacency[from_n] = []
            adjacency[from_n].append(to_n)

        # BFS from Render Layers to find what is reachable
        render_layers = [n.name for n in nodes if n.bl_idname == "CompositorNodeRLayers"]
        
        reachable = set()
        queue = list(render_layers)
        while queue:
            curr = queue.pop(0)
            if curr in reachable: continue
            reachable.add(curr)
            for neighbor in adjacency.get(curr, []):
                queue.append(neighbor)
        
        # Check if Composite output is reachable
        composite_nodes = [n for n in nodes if n.bl_idname == "CompositorNodeComposite"]
        composite_reachable = any(n.name in reachable for n in composite_nodes)

        # Check if effects are in the reachable set
        # Note: This is a simplification; strictly they should be on the PATH to composite, 
        # but being reachable from Render Layers is a strong enough proxy for this task level.
        glare_reachable = any(n.name in reachable for n in nodes if n.bl_idname == "CompositorNodeGlare")
        cb_reachable = any(n.name in reachable for n in nodes if n.bl_idname == "CompositorNodeColorBalance")
        ld_reachable = any(n.name in reachable for n in nodes if n.bl_idname == "CompositorNodeLensdist")

        result["nodes_connected_chain"] = composite_reachable and glare_reachable and cb_reachable and ld_reachable
        result["chain_details"] = {
            "render_layers_found": len(render_layers) > 0,
            "composite_reachable": composite_reachable,
            "glare_reachable": glare_reachable,
            "color_balance_reachable": cb_reachable,
            "lens_distortion_reachable": ld_reachable
        }

    print("COMPOSITOR_JSON:" + json.dumps(result))

except Exception as e:
    print(f"Error: {e}")
ANALYZE_EOF

    # Run analysis script
    COMPOSITOR_OUTPUT=$(su - ga -c "/opt/blender/blender --background --python /tmp/analyze_compositor.py -- '$BLEND_FILE'" 2>/dev/null | grep "^COMPOSITOR_JSON:" | head -1 | sed 's/^COMPOSITOR_JSON://')
    
    if [ -z "$COMPOSITOR_OUTPUT" ]; then
        COMPOSITOR_OUTPUT="{}"
        echo "WARNING: Could not parse Blender output"
    fi
else
    COMPOSITOR_OUTPUT="{}"
    echo "Blend file not valid, skipping compositor analysis"
fi

# --- Assemble final result JSON ---
python3 << PYEOF
import json

try:
    compositor = json.loads('''$COMPOSITOR_OUTPUT''')
except:
    compositor = {}

result = {
    "task_start_time": int("$TASK_START"),
    "task_end_time": int("$TASK_END"),
    "compositor_analysis": compositor,
    "render_output": {
        "exists": $( [ "$RENDER_EXISTS" = "true" ] && echo "true" || echo "false" ),
        "size_kb": $RENDER_SIZE_KB,
        "width": $RENDER_WIDTH,
        "height": $RENDER_HEIGHT,
        "mtime": int("$RENDER_TIME")
    },
    "blend_file": {
        "exists": $( [ "$BLEND_EXISTS" = "true" ] && echo "true" || echo "false" ),
        "valid": $( [ "$BLEND_VALID" = "true" ] && echo "true" || echo "false" ),
        "size_kb": $BLEND_SIZE_KB,
        "mtime": int("$BLEND_MTIME") if "$BLEND_EXISTS" == "true" else 0
    }
}

with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="