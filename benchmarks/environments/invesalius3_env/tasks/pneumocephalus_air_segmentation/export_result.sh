#!/bin/bash
# Export result for pneumocephalus_air_segmentation task

echo "=== Exporting pneumocephalus_air_segmentation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import struct, os, json, tarfile, plistlib

stl_path     = "/home/ga/Documents/air_analysis/air_spaces.stl"
inv3_path    = "/home/ga/Documents/air_analysis/pneumocephalus_study.inv3"

result = {
    "stl_file_exists":        False,
    "stl_file_size_bytes":    0,
    "stl_valid":              False,
    "stl_is_binary":          False,
    "stl_triangle_count":     0,
    "project_file_exists":    False,
    "project_valid_inv3":     False,
    "mask_count":             0,
    "surface_count":          0,
    "measurement_count":      0,
    "measurements":           [],
    "air_mask_found":         False,   # mask with max_hu <= -200
    "air_mask_max_hu":        None,
    "soft_tissue_mask_found": False,   # mask with min >= -200 and max >= 50
    "soft_tissue_mask_max_hu": None,
    "masks_detail":           [],
}

# --- Analyse STL file ---
if os.path.isfile(stl_path):
    result["stl_file_exists"] = True
    result["stl_file_size_bytes"] = os.path.getsize(stl_path)

    if result["stl_file_size_bytes"] >= 84:
        try:
            with open(stl_path, "rb") as f:
                f.read(80)
                count_bytes = f.read(4)
                if len(count_bytes) == 4:
                    count = struct.unpack("<I", count_bytes)[0]
                    expected_size = 80 + 4 + count * 50
                    if abs(expected_size - result["stl_file_size_bytes"]) <= 512:
                        result["stl_is_binary"]    = True
                        result["stl_triangle_count"] = count
                        result["stl_valid"]         = True
        except Exception:
            pass

    if not result["stl_valid"]:
        try:
            with open(stl_path, "r", errors="replace") as f:
                first_line = f.readline().strip().lower()
            if first_line.startswith("solid"):
                count = 0
                with open(stl_path, "r", errors="replace") as f:
                    for line in f:
                        if line.strip().lower().startswith("facet normal"):
                            count += 1
                if count > 0:
                    result["stl_valid"]         = True
                    result["stl_triangle_count"] = count
        except Exception:
            pass

# --- Analyse InVesalius project file ---
if os.path.isfile(inv3_path):
    result["project_file_exists"] = True
    try:
        with tarfile.open(inv3_path, "r:gz") as t:
            result["project_valid_inv3"] = True
            # collect mask files
            mask_plists = {}
            for member in t.getmembers():
                name = os.path.basename(member.name)
                if name == "main.plist":
                    f = t.extractfile(member)
                    main = plistlib.load(f)
                    result["mask_count"]    = len(main.get("masks", {}))
                    result["surface_count"] = len(main.get("surfaces", {}))
                elif name.startswith("mask_") and name.endswith(".plist"):
                    f = t.extractfile(member)
                    mp = plistlib.load(f)
                    mask_plists[name] = mp
                elif name == "measurements.plist":
                    f = t.extractfile(member)
                    meas_dict = plistlib.load(f)
                    result["measurement_count"] = len(meas_dict)
                    for idx, meas in meas_dict.items():
                        val = float(meas.get("value", 0))
                        result["measurements"].append({"index": str(idx), "value_mm": val})

            # Analyse mask HU ranges
            for mask_name, mp in mask_plists.items():
                tr = mp.get("threshold_range", [0, 0])
                min_hu = float(tr[0]) if len(tr) >= 1 else 0.0
                max_hu = float(tr[1]) if len(tr) >= 2 else 0.0
                result["masks_detail"].append({
                    "name": mask_name,
                    "min_hu": min_hu,
                    "max_hu": max_hu,
                })
                # Air mask: max_hu <= -200
                if max_hu <= -200:
                    result["air_mask_found"] = True
                    if result["air_mask_max_hu"] is None or max_hu > result["air_mask_max_hu"]:
                        result["air_mask_max_hu"] = max_hu
                # Soft tissue mask: min_hu >= -200 AND max_hu >= 50
                if min_hu >= -200 and max_hu >= 50:
                    result["soft_tissue_mask_found"] = True
                    result["soft_tissue_mask_max_hu"] = max_hu

    except Exception as e:
        result["project_parse_error"] = str(e)

with open("/tmp/pneumocephalus_air_segmentation_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
