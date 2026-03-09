#!/bin/bash
# Export result for measure_skull_and_save task

echo "=== Exporting measure_skull_and_save result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import tarfile, plistlib, os, json

inv3_path = "/home/ga/Documents/cranial_measurements.inv3"

result = {
    "file_exists": False,
    "valid_inv3": False,
    "measurement_count": 0,
    "measurements": [],
    "measurements_above_80mm": 0,
}

if os.path.isfile(inv3_path):
    result["file_exists"] = True
    try:
        with tarfile.open(inv3_path, "r:gz") as t:
            result["valid_inv3"] = True
            for member in t.getmembers():
                name = os.path.basename(member.name)
                if name == "measurements.plist":
                    f = t.extractfile(member)
                    meas_dict = plistlib.load(f)
                    result["measurement_count"] = len(meas_dict)
                    for idx, meas in meas_dict.items():
                        val = float(meas.get("value", 0))
                        result["measurements"].append({
                            "index": idx,
                            "value_mm": val,
                        })
                    result["measurements_above_80mm"] = sum(
                        1 for m in result["measurements"] if m["value_mm"] > 80.0
                    )
    except Exception as e:
        result["parse_error"] = str(e)

with open("/tmp/measure_skull_and_save_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
