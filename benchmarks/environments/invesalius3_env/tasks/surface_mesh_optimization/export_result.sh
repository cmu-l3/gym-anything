#!/bin/bash
# Export result for surface_mesh_optimization task

echo "=== Exporting surface_mesh_optimization result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import struct, os, json, tarfile, plistlib

ply_path     = "/home/ga/Documents/skull_optimized.ply"
stl_path     = "/home/ga/Documents/skull_optimized.stl"
inv3_path    = "/home/ga/Documents/mesh_optimization.inv3"

result = {
    "ply_file_exists":     False,
    "ply_file_size_bytes": 0,
    "ply_valid":           False,
    "ply_vertex_count":    0,
    "ply_face_count":      0,
    "stl_file_exists":     False,
    "stl_file_size_bytes": 0,
    "stl_valid":           False,
    "stl_triangle_count":  0,
    "project_file_exists": False,
    "project_valid_inv3":  False,
    "mask_count":          0,
    "surface_count":       0,
}

# --- Analyse PLY file ---
if os.path.isfile(ply_path):
    result["ply_file_exists"] = True
    result["ply_file_size_bytes"] = os.path.getsize(ply_path)
    try:
        vertex_count = 0
        face_count = 0
        with open(ply_path, "rb") as f:
            # Read header lines
            header_lines = []
            while True:
                line = f.readline().decode("ascii", errors="replace").strip()
                header_lines.append(line)
                if line == "end_header":
                    break
                if len(header_lines) > 200:
                    break
            header_text = "\n".join(header_lines)
            if header_lines[0].lower() == "ply":
                result["ply_valid"] = True
                import re
                vm = re.search(r"element vertex\s+(\d+)", header_text)
                if vm:
                    vertex_count = int(vm.group(1))
                fm = re.search(r"element face\s+(\d+)", header_text)
                if fm:
                    face_count = int(fm.group(1))
        result["ply_vertex_count"] = vertex_count
        result["ply_face_count"] = face_count
    except Exception as e:
        result["ply_parse_error"] = str(e)

# --- Analyse STL file ---
if os.path.isfile(stl_path):
    result["stl_file_exists"] = True
    result["stl_file_size_bytes"] = os.path.getsize(stl_path)

    if result["stl_file_size_bytes"] >= 84:
        try:
            with open(stl_path, "rb") as f:
                f.read(80)
                cb = f.read(4)
                if len(cb) == 4:
                    count = struct.unpack("<I", cb)[0]
                    if abs((80 + 4 + count * 50) - result["stl_file_size_bytes"]) <= 512:
                        result["stl_valid"] = True
                        result["stl_triangle_count"] = count
        except Exception:
            pass

    if not result["stl_valid"]:
        try:
            with open(stl_path, "r", errors="replace") as f:
                if f.readline().strip().lower().startswith("solid"):
                    count = sum(1 for ln in f if ln.strip().lower().startswith("facet normal"))
                    if count > 0:
                        result["stl_valid"] = True
                        result["stl_triangle_count"] = count
        except Exception:
            pass

# --- Analyse InVesalius project ---
if os.path.isfile(inv3_path):
    result["project_file_exists"] = True
    try:
        with tarfile.open(inv3_path, "r:gz") as t:
            result["project_valid_inv3"] = True
            for member in t.getmembers():
                name = os.path.basename(member.name)
                if name == "main.plist":
                    f = t.extractfile(member)
                    main = plistlib.load(f)
                    result["mask_count"] = len(main.get("masks", {}))
                    result["surface_count"] = len(main.get("surfaces", {}))
    except Exception as e:
        result["project_parse_error"] = str(e)

with open("/tmp/surface_mesh_optimization_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
