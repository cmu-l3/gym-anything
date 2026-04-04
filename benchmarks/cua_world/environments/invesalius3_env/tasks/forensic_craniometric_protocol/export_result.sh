#!/bin/bash
# Export result for forensic_craniometric_protocol task

echo "=== Exporting forensic_craniometric_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import struct, os, json, tarfile, plistlib

output_dir   = "/home/ga/Documents/forensic_case"
stl_path     = os.path.join(output_dir, "skull_surface.stl")
inv3_path    = os.path.join(output_dir, "forensic_analysis.inv3")

png_files = {
    "norma_frontalis":  os.path.join(output_dir, "norma_frontalis.png"),
    "norma_lateralis":  os.path.join(output_dir, "norma_lateralis.png"),
    "norma_verticalis": os.path.join(output_dir, "norma_verticalis.png"),
}

PNG_MAGIC = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

def check_png(path):
    info = {"exists": False, "valid_png": False, "size_bytes": 0}
    if not os.path.isfile(path):
        return info
    info["exists"]     = True
    info["size_bytes"] = os.path.getsize(path)
    try:
        with open(path, "rb") as f:
            magic = f.read(8)
        info["valid_png"] = (magic == PNG_MAGIC)
    except Exception:
        pass
    return info

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
                cnt_bytes = f.read(4)
            if len(cnt_bytes) == 4:
                count = struct.unpack("<I", cnt_bytes)[0]
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
                info["valid"]          = True
                info["triangle_count"] = count
    except Exception:
        pass
    return info

result = {
    "project_file_exists":    False,
    "project_valid_inv3":     False,
    "mask_count":             0,
    "surface_count":          0,
    "measurement_count":      0,
    "measurements":           [],
    "measurements_above_15mm": 0,
}

for key, path in png_files.items():
    result[f"png_{key}"] = check_png(path)

result["stl"] = parse_stl(stl_path)

if os.path.isfile(inv3_path):
    result["project_file_exists"] = True
    try:
        with tarfile.open(inv3_path, "r:gz") as t:
            result["project_valid_inv3"] = True
            for member in t.getmembers():
                bname = os.path.basename(member.name)
                if bname == "main.plist":
                    f = t.extractfile(member)
                    main = plistlib.load(f)
                    result["mask_count"]    = len(main.get("masks", {}))
                    result["surface_count"] = len(main.get("surfaces", {}))
                elif bname == "measurements.plist":
                    f = t.extractfile(member)
                    meas_dict = plistlib.load(f)
                    result["measurement_count"] = len(meas_dict)
                    for idx, meas in meas_dict.items():
                        val = float(meas.get("value", 0))
                        result["measurements"].append({"index": str(idx), "value_mm": val})
                    result["measurements_above_15mm"] = sum(
                        1 for m in result["measurements"] if m["value_mm"] >= 15.0
                    )
    except Exception as e:
        result["project_parse_error"] = str(e)

with open("/tmp/forensic_craniometric_protocol_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
