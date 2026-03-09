#!/bin/bash
# Export result for cranioplasty_implant_pipeline task

echo "=== Exporting cranioplasty_implant_pipeline result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

python3 << 'PYEOF'
import struct, os, json, tarfile, plistlib, re

output_dir   = "/home/ga/Documents/cranioplasty"
ply_path     = os.path.join(output_dir, "cortical_bone.ply")
stl_path     = os.path.join(output_dir, "cancellous_bone.stl")
inv3_path    = os.path.join(output_dir, "implant_fabrication.inv3")

result = {
    "ply_exists":           False,
    "ply_valid":            False,
    "ply_vertex_count":     0,
    "ply_face_count":       0,
    "ply_size_bytes":       0,
    "stl_exists":           False,
    "stl_valid":            False,
    "stl_triangle_count":   0,
    "stl_size_bytes":       0,
    "project_file_exists":  False,
    "project_valid_inv3":   False,
    "mask_count":           0,
    "surface_count":        0,
    "measurement_count":    0,
    "measurements":         [],
    "measurements_above_10mm": 0,
    "masks_detail":         [],
}

# --- Analyse PLY file ---
if os.path.isfile(ply_path):
    result["ply_exists"]     = True
    result["ply_size_bytes"] = os.path.getsize(ply_path)
    try:
        with open(ply_path, "rb") as f:
            # Read up to 2048 bytes for header
            header_raw = f.read(2048)
        header_text = header_raw.decode("ascii", errors="replace")
        lines = header_text.splitlines()
        if lines and lines[0].strip().lower().startswith("ply"):
            result["ply_valid"] = True
            for line in lines:
                line = line.strip()
                vm = re.match(r"element\s+vertex\s+(\d+)", line, re.IGNORECASE)
                if vm:
                    result["ply_vertex_count"] = int(vm.group(1))
                fm = re.match(r"element\s+face\s+(\d+)", line, re.IGNORECASE)
                if fm:
                    result["ply_face_count"] = int(fm.group(1))
    except Exception as e:
        result["ply_parse_error"] = str(e)

# --- Analyse STL file ---
if os.path.isfile(stl_path):
    result["stl_exists"]     = True
    result["stl_size_bytes"] = os.path.getsize(stl_path)
    if result["stl_size_bytes"] >= 84:
        try:
            with open(stl_path, "rb") as f:
                f.read(80)
                cnt = f.read(4)
            if len(cnt) == 4:
                count = struct.unpack("<I", cnt)[0]
                if abs((80 + 4 + count * 50) - result["stl_size_bytes"]) <= 512:
                    result["stl_valid"]          = True
                    result["stl_triangle_count"] = count
        except Exception:
            pass
    if not result["stl_valid"]:
        try:
            with open(stl_path, "r", errors="replace") as f:
                first = f.readline().strip().lower()
            if first.startswith("solid"):
                count = sum(
                    1 for ln in open(stl_path, "r", errors="replace")
                    if ln.strip().lower().startswith("facet normal")
                )
                if count > 0:
                    result["stl_valid"]          = True
                    result["stl_triangle_count"] = count
        except Exception:
            pass

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
                        val = float(meas.get("value", 0))
                        result["measurements"].append({"index": str(idx), "value_mm": val})
                    result["measurements_above_10mm"] = sum(
                        1 for m in result["measurements"] if m["value_mm"] >= 10.0
                    )

            for name, mp in mask_plists.items():
                tr = mp.get("threshold_range", [0, 0])
                min_hu = float(tr[0]) if len(tr) >= 1 else 0.0
                max_hu = float(tr[1]) if len(tr) >= 2 else 0.0
                result["masks_detail"].append({"name": name, "min_hu": min_hu, "max_hu": max_hu})

    except Exception as e:
        result["project_parse_error"] = str(e)

with open("/tmp/cranioplasty_implant_pipeline_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
