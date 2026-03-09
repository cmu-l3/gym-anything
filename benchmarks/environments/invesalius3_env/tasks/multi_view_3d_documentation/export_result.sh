#!/bin/bash
# Export result for multi_view_3d_documentation task

echo "=== Exporting multi_view_3d_documentation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import os, json, tarfile, plistlib

views_dir = "/home/ga/Documents/surgical_views"
inv3_path = os.path.join(views_dir, "skull_study.inv3")

png_files = {
    "anterior_view":  os.path.join(views_dir, "anterior_view.png"),
    "lateral_view":   os.path.join(views_dir, "lateral_view.png"),
    "superior_view":  os.path.join(views_dir, "superior_view.png"),
}

PNG_MAGIC = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

def check_png(path):
    info = {"exists": False, "valid_png": False, "size_bytes": 0}
    if not os.path.isfile(path):
        return info
    info["exists"] = True
    info["size_bytes"] = os.path.getsize(path)
    try:
        with open(path, "rb") as f:
            magic = f.read(8)
        info["valid_png"] = (magic == PNG_MAGIC)
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
    "measurements_above_30mm": 0,
}

for key, path in png_files.items():
    result[f"png_{key}"] = check_png(path)

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
                elif name == "measurements.plist":
                    f = t.extractfile(member)
                    meas_dict = plistlib.load(f)
                    result["measurement_count"] = len(meas_dict)
                    for idx, meas in meas_dict.items():
                        val = float(meas.get("value", 0))
                        result["measurements"].append({"index": str(idx), "value_mm": val})
                    result["measurements_above_30mm"] = sum(
                        1 for m in result["measurements"] if m["value_mm"] >= 30.0
                    )
    except Exception as e:
        result["project_parse_error"] = str(e)

with open("/tmp/multi_view_3d_documentation_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
