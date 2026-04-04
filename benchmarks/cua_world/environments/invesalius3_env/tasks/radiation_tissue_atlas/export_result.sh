#!/bin/bash
# Export result for radiation_tissue_atlas task

echo "=== Exporting radiation_tissue_atlas result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import struct, os, json, tarfile, plistlib

output_dir   = "/home/ga/Documents/rt_planning"
inv3_path    = os.path.join(output_dir, "rt_tissue_atlas.inv3")
stl_paths    = {
    "brain_tissue":    os.path.join(output_dir, "brain_tissue.stl"),
    "skull_bone":      os.path.join(output_dir, "skull_bone.stl"),
    "periorbital_fat": os.path.join(output_dir, "periorbital_fat.stl"),
}

def parse_stl(path):
    info = {"exists": False, "valid": False, "triangle_count": 0, "size_bytes": 0}
    if not os.path.isfile(path):
        return info
    info["exists"]     = True
    info["size_bytes"] = os.path.getsize(path)
    if info["size_bytes"] >= 84:
        try:
            with open(path, "rb") as f:
                f.read(80)
                cnt = f.read(4)
            if len(cnt) == 4:
                count = struct.unpack("<I", cnt)[0]
                if abs((80 + 4 + count * 50) - info["size_bytes"]) <= 512:
                    info["valid"]          = True
                    info["triangle_count"] = count
                    return info
        except Exception:
            pass
    # ASCII fallback
    try:
        with open(path, "r", errors="replace") as f:
            first = f.readline().strip().lower()
        if first.startswith("solid"):
            count = sum(
                1 for ln in open(path, "r", errors="replace")
                if ln.strip().lower().startswith("facet normal")
            )
            if count > 0:
                info["valid"] = True
                info["triangle_count"] = count
    except Exception:
        pass
    return info

result = {
    "project_file_exists": False,
    "project_valid_inv3":  False,
    "mask_count":          0,
    "surface_count":       0,
    "measurement_count":   0,
    "measurements":        [],
    "masks_detail":        [],
    # mask classification flags (set after HU analysis)
    "brain_mask_found":    False,
    "bone_mask_found":     False,
    "fat_mask_found":      False,
}

for key, path in stl_paths.items():
    result[f"stl_{key}"] = parse_stl(path)

# --- Analyse InVesalius project ---
if os.path.isfile(inv3_path):
    result["project_file_exists"] = True
    try:
        with tarfile.open(inv3_path, "r:gz") as t:
            result["project_valid_inv3"] = True
            mask_plists = {}
            for member in t.getmembers():
                bname = os.path.basename(member.name)
                if bname == "main.plist":
                    f = t.extractfile(member)
                    main = plistlib.load(f)
                    result["mask_count"]    = len(main.get("masks", {}))
                    result["surface_count"] = len(main.get("surfaces", {}))
                elif bname.startswith("mask_") and bname.endswith(".plist"):
                    f = t.extractfile(member)
                    mask_plists[bname] = plistlib.load(f)
                elif bname == "measurements.plist":
                    f = t.extractfile(member)
                    meas_dict = plistlib.load(f)
                    result["measurement_count"] = len(meas_dict)
                    for idx, meas in meas_dict.items():
                        result["measurements"].append(
                            {"index": str(idx), "value_mm": float(meas.get("value", 0))}
                        )

            for name, mp in mask_plists.items():
                tr = mp.get("threshold_range", [0, 0])
                min_hu = float(tr[0]) if len(tr) >= 1 else 0.0
                max_hu = float(tr[1]) if len(tr) >= 2 else 0.0
                detail = {"name": name, "min_hu": min_hu, "max_hu": max_hu}
                result["masks_detail"].append(detail)
                # Brain: min >= -100 AND max <= 80
                if min_hu >= -100 and max_hu <= 80:
                    result["brain_mask_found"] = True
                # Bone: min >= 600
                if min_hu >= 600:
                    result["bone_mask_found"] = True
                # Fat: max <= -20 AND min >= -300
                if max_hu <= -20 and min_hu >= -300:
                    result["fat_mask_found"] = True

    except Exception as e:
        result["project_parse_error"] = str(e)

with open("/tmp/radiation_tissue_atlas_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
