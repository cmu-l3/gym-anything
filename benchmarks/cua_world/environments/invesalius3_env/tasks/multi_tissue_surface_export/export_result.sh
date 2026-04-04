#!/bin/bash
# Export result for multi_tissue_surface_export task

echo "=== Exporting multi_tissue_surface_export result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import struct, os, json, tarfile, plistlib

output_dir = "/home/ga/Documents/tissue_exports"
inv3_path  = os.path.join(output_dir, "tissue_analysis.inv3")

stl_files = {
    "bone_tissue":  os.path.join(output_dir, "bone_tissue.stl"),
    "compact_bone": os.path.join(output_dir, "compact_bone.stl"),
    "soft_tissue":  os.path.join(output_dir, "soft_tissue.stl"),
}

def parse_stl(path):
    info = {"exists": False, "valid": False, "triangle_count": 0, "size_bytes": 0}
    if not os.path.isfile(path):
        return info
    info["exists"] = True
    info["size_bytes"] = os.path.getsize(path)
    # Try binary STL
    if info["size_bytes"] >= 84:
        try:
            with open(path, "rb") as f:
                f.read(80)
                cb = f.read(4)
                if len(cb) == 4:
                    count = struct.unpack("<I", cb)[0]
                    if abs((80 + 4 + count * 50) - info["size_bytes"]) <= 512:
                        info["valid"] = True
                        info["triangle_count"] = count
                        return info
        except Exception:
            pass
    # Try ASCII STL
    try:
        with open(path, "r", errors="replace") as f:
            if f.readline().strip().lower().startswith("solid"):
                count = sum(1 for ln in f if ln.strip().lower().startswith("facet normal"))
                if count > 0:
                    info["valid"] = True
                    info["triangle_count"] = count
    except Exception:
        pass
    return info

result = {
    "project_file_exists": False,
    "project_valid_inv3": False,
    "mask_count": 0,
    "masks": [],
    "has_bone_mask":         False,
    "has_compact_bone_mask": False,
    "has_soft_tissue_mask":  False,
    "surface_count": 0,
}

for key, path in stl_files.items():
    result[f"stl_{key}"] = parse_stl(path)

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
                    # Full bone mask: min >= 226
                    if thresh[0] >= 226 and thresh[1] >= 1000:
                        result["has_bone_mask"] = True
                    # Compact bone: min >= 662
                    if thresh[0] >= 662:
                        result["has_compact_bone_mask"] = True
                    # Soft tissue: max <= 225
                    if thresh[1] <= 225:
                        result["has_soft_tissue_mask"] = True
    except Exception as e:
        result["project_parse_error"] = str(e)

with open("/tmp/multi_tissue_surface_export_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
