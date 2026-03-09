#!/bin/bash
echo "=== Exporting multi_object_scene_assembly result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_BLEND="/home/ga/BlenderProjects/showcase_scene.blend"

# ================================================================
# GET INITIAL STATE
# ================================================================
INITIAL_OBJECT_COUNT="0"
INITIAL_MESH_COUNT="0"
INITIAL_MATERIAL_COUNT="0"

if [ -f /tmp/initial_state.json ]; then
    INITIAL_OBJECT_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_scene', {}).get('object_count', 0))" 2>/dev/null || echo "0")
    INITIAL_MESH_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_scene', {}).get('mesh_count', 0))" 2>/dev/null || echo "0")
    INITIAL_MATERIAL_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_scene', {}).get('material_count', 0))" 2>/dev/null || echo "0")
fi

# ================================================================
# CHECK OUTPUT FILE EXISTS
# ================================================================
if [ -f "$OUTPUT_BLEND" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_BLEND" 2>/dev/null || echo "0")

    # Check if file is valid blend file (magic bytes)
    IS_VALID_BLEND="false"
    MAGIC=$(head -c 7 "$OUTPUT_BLEND" 2>/dev/null | tr -d '\0')
    if [ "$MAGIC" = "BLENDER" ]; then
        IS_VALID_BLEND="true"
    fi

    # ================================================================
    # ANALYZE THE SCENE VIA BLENDER PYTHON (headless)
    # ================================================================
    SCENE_ANALYSIS=$(python3 << 'PYEOF'
import subprocess
import json
import math

script = '''
import bpy
import json
import math

bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/showcase_scene.blend")

# ------------------------------------------------------------------
# Collect all objects with type info
# ------------------------------------------------------------------
objects = []
mesh_objects = []
light_objects = []
camera_objects = []

for obj in bpy.data.objects:
    obj_info = {
        "name": obj.name,
        "type": obj.type,
        "location": [round(obj.location.x, 4), round(obj.location.y, 4), round(obj.location.z, 4)]
    }

    if obj.type == "MESH" and obj.data:
        mesh = obj.data
        # Collect mesh geometry info for type detection
        obj_info["vertex_count"] = len(mesh.vertices)
        obj_info["face_count"] = len(mesh.polygons)
        obj_info["edge_count"] = len(mesh.edges)

        # Compute bounding box dimensions in world space
        bbox_corners = [obj.matrix_world @ bpy.mathutils.Vector(c) for c in obj.bound_box] if hasattr(bpy, 'mathutils') else []
        if not bbox_corners:
            import mathutils
            bbox_corners = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
        xs = [c.x for c in bbox_corners]
        ys = [c.y for c in bbox_corners]
        zs = [c.z for c in bbox_corners]
        obj_info["bbox_size"] = [
            round(max(xs) - min(xs), 4),
            round(max(ys) - min(ys), 4),
            round(max(zs) - min(zs), 4)
        ]

        # Collect assigned materials
        mat_list = []
        for slot in obj.material_slots:
            if slot.material:
                mat_info = {"name": slot.material.name}
                # Get base color from Principled BSDF if available
                if slot.material.use_nodes:
                    for node in slot.material.node_tree.nodes:
                        if node.type == 'BSDF_PRINCIPLED':
                            bc = node.inputs['Base Color'].default_value
                            mat_info["base_color"] = [round(bc[0], 4), round(bc[1], 4), round(bc[2], 4), round(bc[3], 4)]
                            break
                else:
                    dc = slot.material.diffuse_color
                    mat_info["base_color"] = [round(dc[0], 4), round(dc[1], 4), round(dc[2], 4), round(dc[3], 4)]
                mat_list.append(mat_info)
        obj_info["materials"] = mat_list

        mesh_objects.append(obj_info)
    elif obj.type == "LIGHT":
        obj_info["light_type"] = obj.data.type
        obj_info["energy"] = round(obj.data.energy, 4)
        light_objects.append(obj_info)
    elif obj.type == "CAMERA":
        camera_objects.append(obj_info)

    objects.append(obj_info)

# ------------------------------------------------------------------
# Detect mesh types by name (case-insensitive)
# ------------------------------------------------------------------
detected_types = {}
type_keywords = {
    "sphere": ["sphere", "uvsphere", "uv_sphere", "icosphere"],
    "cube": ["cube", "box"],
    "cylinder": ["cylinder"],
    "cone": ["cone"],
    "torus": ["torus", "donut"]
}

for mobj in mesh_objects:
    name_lower = mobj["name"].lower().replace(" ", "").replace("_", "")
    for mesh_type, keywords in type_keywords.items():
        for kw in keywords:
            if kw.replace("_", "") in name_lower:
                if mesh_type not in detected_types:
                    detected_types[mesh_type] = []
                detected_types[mesh_type].append(mobj["name"])
                break

# Fallback: try vertex/face count heuristics for undetected types
# Cube: 8 verts, 6 faces
# Cylinder: 64-96 verts typically
# Cone: 33-65 verts typically
# Torus: 576+ verts typically (48x12 default)
# UV Sphere: 482+ verts typically (32x16 default)
already_assigned = set()
for t in detected_types.values():
    already_assigned.update(t)

for mobj in mesh_objects:
    if mobj["name"] in already_assigned:
        continue
    vc = mobj.get("vertex_count", 0)
    fc = mobj.get("face_count", 0)

    if vc == 8 and fc == 6 and "cube" not in detected_types:
        detected_types["cube"] = detected_types.get("cube", []) + [mobj["name"]]
        already_assigned.add(mobj["name"])

# ------------------------------------------------------------------
# Collect unique materials across all mesh objects
# ------------------------------------------------------------------
all_materials = {}
for mobj in mesh_objects:
    for mat in mobj.get("materials", []):
        mat_name = mat["name"]
        if mat_name not in all_materials:
            all_materials[mat_name] = mat.get("base_color", [0.8, 0.8, 0.8, 1.0])

# ------------------------------------------------------------------
# Compute pairwise distances between mesh objects (excluding ground plane candidates)
# ------------------------------------------------------------------
# A ground plane candidate: name contains "plane" or "ground" or "floor",
# or it is very flat (Z-extent < 0.2) and wide (X or Y extent > 5)
non_ground_meshes = []
ground_planes = []

for mobj in mesh_objects:
    name_lower = mobj["name"].lower()
    bbox = mobj.get("bbox_size", [0, 0, 0])
    is_ground = False

    # Name-based detection
    if any(kw in name_lower for kw in ["plane", "ground", "floor"]):
        is_ground = True
    # Geometry-based detection: very flat and wide
    elif bbox[2] < 0.2 and (bbox[0] > 4.0 or bbox[1] > 4.0):
        is_ground = True

    if is_ground:
        ground_planes.append(mobj)
    else:
        non_ground_meshes.append(mobj)

pairwise_distances = []
min_pairwise_distance = 999.0

for i in range(len(non_ground_meshes)):
    for j in range(i + 1, len(non_ground_meshes)):
        loc_a = non_ground_meshes[i]["location"]
        loc_b = non_ground_meshes[j]["location"]
        dist = math.sqrt(
            (loc_a[0] - loc_b[0]) ** 2 +
            (loc_a[1] - loc_b[1]) ** 2 +
            (loc_a[2] - loc_b[2]) ** 2
        )
        pairwise_distances.append({
            "obj_a": non_ground_meshes[i]["name"],
            "obj_b": non_ground_meshes[j]["name"],
            "distance": round(dist, 4)
        })
        if dist < min_pairwise_distance:
            min_pairwise_distance = dist

if not pairwise_distances:
    min_pairwise_distance = 0.0

# ------------------------------------------------------------------
# Build result
# ------------------------------------------------------------------
result = {
    "object_count": len(bpy.data.objects),
    "mesh_count": len(mesh_objects),
    "material_count": len(bpy.data.materials),
    "light_count": len(light_objects),
    "camera_count": len(camera_objects),
    "objects": objects,
    "mesh_objects": mesh_objects,
    "light_objects": light_objects,
    "camera_objects": camera_objects,
    "detected_mesh_types": detected_types,
    "all_materials": all_materials,
    "unique_material_count": len(all_materials),
    "ground_planes": [g["name"] for g in ground_planes],
    "has_ground_plane": len(ground_planes) > 0,
    "non_ground_mesh_count": len(non_ground_meshes),
    "min_pairwise_distance": round(min_pairwise_distance, 4),
    "pairwise_distances": pairwise_distances
}

print("JSON:" + json.dumps(result))
'''

try:
    result = subprocess.run(
        ["/opt/blender/blender", "--background", "--python-expr", script],
        capture_output=True, text=True, timeout=120
    )
    for line in result.stdout.split('\n'):
        if line.startswith('JSON:'):
            print(line[5:])
            break
    else:
        # Try stderr too in case Blender printed there
        for line in result.stderr.split('\n'):
            if line.startswith('JSON:'):
                print(line[5:])
                break
        else:
            error_msg = result.stderr[-500:] if result.stderr else "no output"
            print(json.dumps({
                "error": f"no JSON output: {error_msg}",
                "object_count": 0, "mesh_count": 0, "material_count": 0,
                "light_count": 0, "camera_count": 0,
                "detected_mesh_types": {}, "all_materials": {},
                "unique_material_count": 0, "has_ground_plane": False,
                "ground_planes": [], "non_ground_mesh_count": 0,
                "min_pairwise_distance": 0.0, "pairwise_distances": [],
                "mesh_objects": [], "light_objects": [], "camera_objects": [],
                "objects": []
            }))
except Exception as e:
    print(json.dumps({
        "error": str(e),
        "object_count": 0, "mesh_count": 0, "material_count": 0,
        "light_count": 0, "camera_count": 0,
        "detected_mesh_types": {}, "all_materials": {},
        "unique_material_count": 0, "has_ground_plane": False,
        "ground_planes": [], "non_ground_mesh_count": 0,
        "min_pairwise_distance": 0.0, "pairwise_distances": [],
        "mesh_objects": [], "light_objects": [], "camera_objects": [],
        "objects": []
    }))
PYEOF
)

    echo "Scene analysis complete"
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    IS_VALID_BLEND="false"
    SCENE_ANALYSIS='{"error":"file_not_found","object_count":0,"mesh_count":0,"material_count":0,"light_count":0,"camera_count":0,"detected_mesh_types":{},"all_materials":{},"unique_material_count":0,"has_ground_plane":false,"ground_planes":[],"non_ground_mesh_count":0,"min_pairwise_distance":0.0,"pairwise_distances":[],"mesh_objects":[],"light_objects":[],"camera_objects":[],"objects":[]}'
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

python3 << PYEOF
import json

# Load the scene analysis
try:
    scene = json.loads('''$SCENE_ANALYSIS''')
except:
    scene = {"error": "parse_failed"}

result = {
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_path": "$OUTPUT_BLEND",
    "is_valid_blend": $IS_VALID_BLEND,
    "initial_object_count": $INITIAL_OBJECT_COUNT,
    "initial_mesh_count": $INITIAL_MESH_COUNT,
    "initial_material_count": $INITIAL_MATERIAL_COUNT,
    "scene_analysis": scene,
    "blender_was_running": $BLENDER_RUNNING,
    "blender_window_title": "$BLENDER_WINDOW_TITLE",
    "screenshot_path": "/tmp/task_end.png",
    "initial_screenshot_path": "/tmp/task_start.png",
    "timestamp": "$(date -Iseconds)"
}

with open("$TEMP_JSON", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
