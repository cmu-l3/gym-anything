#!/bin/bash
# Export result for configure_window_level_save task

echo "=== Exporting configure_window_level_save result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import tarfile, plistlib, os, json

inv3_path = "/home/ga/Documents/brain_study.inv3"

result = {
    "file_exists": False,
    "valid_inv3": False,
    "window_width": 406.0,
    "window_level": 0.0,
    "window_width_changed": False,
    "mask_count": 0,
    "masks": [],
    "has_soft_tissue_mask": False,
}

DEFAULT_WINDOW_WIDTH = 406.0

if os.path.isfile(inv3_path):
    result["file_exists"] = True
    try:
        with tarfile.open(inv3_path, "r:gz") as t:
            result["valid_inv3"] = True
            for member in t.getmembers():
                name = os.path.basename(member.name)
                if name == "main.plist":
                    f = t.extractfile(member)
                    main = plistlib.load(f)
                    result["window_width"] = float(main.get("window_width", DEFAULT_WINDOW_WIDTH))
                    result["window_level"] = float(main.get("window_level", 0.0))
                    result["mask_count"] = len(main.get("masks", {}))
                    # Window width changed if substantially narrower than default bone window
                    result["window_width_changed"] = result["window_width"] <= 250.0
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
                    # Soft tissue: max HU <= 300
                    if thresh[1] <= 300:
                        result["has_soft_tissue_mask"] = True
    except Exception as e:
        result["parse_error"] = str(e)

with open("/tmp/configure_window_level_save_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
