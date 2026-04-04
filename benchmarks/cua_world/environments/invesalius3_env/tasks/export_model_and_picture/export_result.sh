#!/bin/bash
# Export result for export_model_and_picture task

echo "=== Exporting export_model_and_picture result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import os, json

obj_path = "/home/ga/Documents/skull_surface.obj"
png_path = "/home/ga/Documents/surgical_view.png"

result = {
    "obj_exists": False,
    "obj_size_bytes": 0,
    "obj_vertex_count": 0,
    "obj_face_count": 0,
    "obj_valid": False,
    "png_exists": False,
    "png_size_bytes": 0,
    "png_valid": False,
}

# --- OBJ file analysis ---
if os.path.isfile(obj_path):
    result["obj_exists"] = True
    result["obj_size_bytes"] = os.path.getsize(obj_path)
    try:
        vertex_count = 0
        face_count = 0
        with open(obj_path, "r", errors="replace") as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith("v "):
                    vertex_count += 1
                elif stripped.startswith("f "):
                    face_count += 1
        result["obj_vertex_count"] = vertex_count
        result["obj_face_count"] = face_count
        result["obj_valid"] = vertex_count > 0
    except Exception as e:
        result["obj_parse_error"] = str(e)

# --- PNG file analysis ---
if os.path.isfile(png_path):
    result["png_exists"] = True
    result["png_size_bytes"] = os.path.getsize(png_path)
    try:
        with open(png_path, "rb") as f:
            magic = f.read(8)
        result["png_valid"] = (magic == b"\x89PNG\r\n\x1a\n")
    except Exception as e:
        result["png_parse_error"] = str(e)

with open("/tmp/export_model_and_picture_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
