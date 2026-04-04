#!/bin/bash
# Export result for boolean_mask_operations task

echo "=== Exporting boolean_mask_operations result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import struct, os, json, tarfile, plistlib

stl_path  = "/home/ga/Documents/cancellous_study/cancellous_bone.stl"
inv3_path = "/home/ga/Documents/cancellous_study/bone_analysis.inv3"

result = {
    "stl_file_exists": False,
    "stl_file_size_bytes": 0,
    "stl_valid": False,
    "stl_triangle_count": 0,
    "project_file_exists": False,
    "project_valid_inv3": False,
    "mask_count": 0,
    "masks": [],
    "has_compact_bone_mask": False,
    "has_full_bone_mask": False,
    "surface_count": 0,
}

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
                elif name.startswith("mask_") and name.endswith(".plist"):
                    f = t.extractfile(member)
                    mask = plistlib.load(f)
                    thresh = mask.get("threshold_range", [0, 0])
                    mask_info = {
                        "name": mask.get("name", ""),
                        "threshold_min": thresh[0],
                        "threshold_max": thresh[1],
                    }
                    result["masks"].append(mask_info)
                    # Compact bone: min >= 600, max <= 2100
                    if thresh[0] >= 600 and thresh[1] <= 2100:
                        result["has_compact_bone_mask"] = True
                    # Full bone: min >= 200 and max >= 2000
                    if thresh[0] >= 200 and thresh[1] >= 2000:
                        result["has_full_bone_mask"] = True
    except Exception as e:
        result["project_parse_error"] = str(e)

with open("/tmp/boolean_mask_operations_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
