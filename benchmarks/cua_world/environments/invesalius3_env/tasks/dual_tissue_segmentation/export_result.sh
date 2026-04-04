#!/bin/bash
# Export result for dual_tissue_segmentation task

echo "=== Exporting dual_tissue_segmentation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import tarfile, plistlib, os, json

inv3_path = "/home/ga/Documents/tissue_comparison.inv3"

result = {
    "file_exists": False,
    "file_size_bytes": 0,
    "valid_inv3": False,
    "mask_count": 0,
    "masks": [],
    "has_bone_mask": False,
    "has_soft_tissue_mask": False,
    "surface_count": 0,
    "window_width": 0.0,
    "window_level": 0.0,
}

if os.path.isfile(inv3_path):
    result["file_exists"] = True
    result["file_size_bytes"] = os.path.getsize(inv3_path)
    try:
        with tarfile.open(inv3_path, "r:gz") as t:
            result["valid_inv3"] = True
            for member in t.getmembers():
                name = os.path.basename(member.name)
                if name == "main.plist":
                    f = t.extractfile(member)
                    main = plistlib.load(f)
                    result["window_width"] = float(main.get("window_width", 0))
                    result["window_level"] = float(main.get("window_level", 0))
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
                    # Bone: min HU >= 150, max HU >= 1000
                    if thresh[0] >= 150 and thresh[1] >= 1000:
                        result["has_bone_mask"] = True
                    # Soft tissue: max HU <= 300
                    if thresh[1] <= 300:
                        result["has_soft_tissue_mask"] = True
    except Exception as e:
        result["parse_error"] = str(e)

with open("/tmp/dual_tissue_segmentation_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
