#!/bin/bash
# Export result for implant_sizing_measurements task

echo "=== Exporting implant_sizing_measurements result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import struct, os, json, tarfile, plistlib

stl_path = "/home/ga/Documents/implant_sizing.stl"
inv3_path = "/home/ga/Documents/implant_plan.inv3"

result = {
    "stl_file_exists": False,
    "stl_file_size_bytes": 0,
    "stl_valid": False,
    "stl_is_binary": False,
    "stl_triangle_count": 0,
    "project_file_exists": False,
    "project_valid_inv3": False,
    "measurement_count": 0,
    "measurements": [],
    "measurements_above_50mm": 0,
    "mask_count": 0,
    "surface_count": 0,
}

# --- Analyse STL file ---
if os.path.isfile(stl_path):
    result["stl_file_exists"] = True
    result["stl_file_size_bytes"] = os.path.getsize(stl_path)

    # Try binary STL
    if result["stl_file_size_bytes"] >= 84:
        try:
            with open(stl_path, "rb") as f:
                f.read(80)  # skip header
                count_bytes = f.read(4)
                if len(count_bytes) == 4:
                    count = struct.unpack("<I", count_bytes)[0]
                    expected_size = 80 + 4 + count * 50
                    if abs(expected_size - result["stl_file_size_bytes"]) <= 512:
                        result["stl_is_binary"] = True
                        result["stl_triangle_count"] = count
                        result["stl_valid"] = True
        except Exception:
            pass

    # Try ASCII STL fallback
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
                    result["stl_valid"] = True
                    result["stl_triangle_count"] = count
        except Exception:
            pass

# --- Analyse InVesalius project file ---
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
                    result["measurements_above_50mm"] = sum(
                        1 for m in result["measurements"] if m["value_mm"] >= 50.0
                    )
    except Exception as e:
        result["project_parse_error"] = str(e)

with open("/tmp/implant_sizing_measurements_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
